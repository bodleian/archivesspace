require 'spec_helper'
require_relative 'container_spec_helper'
require_relative 'factories'

describe 'Record transfers' do

  before(:each) do
    @target_repo = create(:unselected_repo, {:repo_code => "TARGET_REPO"})
  end


  it "allows an accession to be transferred from one repository to another" do

    # Picked rights statement here because it's a nested record with its own
    # repo_id column (since the column is needed for a uniqueness check)
    acc_id = create(:json_accession,
                    :rights_statements => [build(:json_rights_statement)]).id

    Accession[acc_id].transfer_to_repository(@target_repo)

    RequestContext.open(:repo_id => @target_repo.id) do
      json = Accession.to_jsonmodel(acc_id)

      JSONModel.parse_reference(json['uri'])[:repository].should eq(@target_repo.uri)
    end

  end


  it "preserves relationships with global records (like subjects)" do
    subject = create(:json_subject)

    acc_id = create(:json_accession,
                    :subjects => [{'ref' => subject.uri}]).id

    Accession[acc_id].transfer_to_repository(@target_repo)

    RequestContext.open(:repo_id => @target_repo.id) do
      json = Accession.to_jsonmodel(acc_id)

      json['subjects'][0]['ref'].should eq(subject.uri)
    end
  end


  it "discards relationships with records from the original repository" do
    resource = create(:json_resource)

    acc_id = create(:json_accession,
                    :related_resources => [{'ref' => resource.uri}]).id

    Accession[acc_id].transfer_to_repository(@target_repo)

    RequestContext.open(:repo_id => @target_repo.id) do
      json = Accession.to_jsonmodel(acc_id)

      json['related_resources'].should eq([])
    end
  end


  it "marks its old URI as deleted" do
    acc_id = create(:json_accession).id

    acc = Accession[acc_id]
    old_uri = acc.uri

    acc.transfer_to_repository(@target_repo)

    Tombstone.filter(:uri => old_uri).count.should eq(1)
  end


  it "creates an event to record the transfer" do
    acc_id = create(:json_accession).id

    acc = Accession[acc_id]
    acc.transfer_to_repository(@target_repo)

    Event.any_repo.all.any? {|e|
      json = Event.to_jsonmodel(e)
      json.linked_records.any? {|l| l['ref'] == acc.uri}
    }
  end


  it "transfers events too (when the event only links to the record being transferred)" do
    acc_id = create(:json_accession).id
    person = create(:json_agent_person)

    acc = Accession[acc_id]

    event = create(:json_event,
           :linked_agents => [{'ref' => person.uri, 'role' => 'transmitter'}],
           :linked_records => [{'ref' => acc.uri, 'role' => 'transfer'}])

    acc.transfer_to_repository(@target_repo)

    RequestContext.open(:repo_id => @target_repo.id) do
      JSONModel.parse_reference(Event.to_jsonmodel(event.id).uri)[:repository].should eq(@target_repo.uri)
    end
  end


  it "clones events that reference other records besides the one being transferred" do
    unrelated_accession = create(:json_accession)
    acc_id = create(:json_accession).id
    person = create(:json_agent_person)

    acc = Accession[acc_id]

    event = create(:json_event,
                   :outcome_note => "a test outcome note",
                   :linked_agents => [{'ref' => person.uri, 'role' => 'transmitter'}],
                   :linked_records => [{'ref' => acc.uri, 'role' => 'transfer'},
                                       {'ref' => unrelated_accession.uri, 'role' => 'transfer'}])

    acc.transfer_to_repository(@target_repo)

    # The original event now has a single linked record
    original_event = Event.to_jsonmodel(event.id)
    original_event['linked_records'].length.should eq(1)
    original_event['linked_records'][0]['ref'].should eq(unrelated_accession.uri)

    # And there's a parallel event in the target repository that cloned the
    # original event.
    Event.any_repo.all.any? {|e|
      (e.repo_id == @target_repo.id) && (e.outcome_note == "a test outcome note")
    }.should be(true)
  end


  it "allows a resource to be transferred from one repository to another" do
    resource = create(:json_resource)

    ao1 = create(:json_archival_object,
                 :title => "hello",
                 :resource => {'ref' => resource.uri})

    ao2 = create(:json_archival_object,
                 :title => "world",
                 :resource => {'ref' => resource.uri},
                 :parent => {'ref' => ao1.uri})


    Resource[resource.id].transfer_to_repository(@target_repo)

    RequestContext.open(:repo_id => @target_repo.id) do
      tree = Resource[resource.id].tree

      tree['children'][0]['title'].should eq('hello')
      tree['children'][0]['children'][0]['title'].should eq('world')
    end
  end

  it "transfers top containers too if they're only referenced by the record being transferred" do
    box1 = create(:json_top_container, :barcode => "box1_barcode")
    box2 = create(:json_top_container, :barcode => "box2_barcode")

    resource = create(:json_resource)
    ao1 = create(:json_archival_object,
                 :title => "hello",
                 :instances => [build_instance(box1), build_instance(box2)],
                 :resource => {'ref' => resource.uri})

    ao2 = create(:json_archival_object,
                 :title => "world",
                 :resource => {'ref' => resource.uri},
                 :parent => {'ref' => ao1.uri})

    Resource[resource.id].transfer_to_repository(@target_repo)

    RequestContext.open(:repo_id => @target_repo.id) do
      instances = ArchivalObject.to_jsonmodel(ao1.id)["instances"]
      instances.length.should eq(2)

      moved_box1 = TopContainer.this_repo[:barcode => 'box1_barcode']
      moved_box2 = TopContainer.this_repo[:barcode => 'box2_barcode']

      # They have indeed moved
      moved_box1.repo_id.should eq(@target_repo.id)
      moved_box2.repo_id.should eq(@target_repo.id)

      # And they have the same ID as the original box
      moved_box1.id.should eq(box1.id)
      moved_box2.id.should eq(box2.id)

      instances.map {|instance| instance['sub_container']['top_container']['ref']}.should include(moved_box1.uri)
      instances.map {|instance| instance['sub_container']['top_container']['ref']}.should include(moved_box2.uri)
    end
  end

  it "clones top containers as needed to preserve the instances of transferred records" do
    box1 = create(:json_top_container, :barcode => "box1_barcode")
    box2 = create(:json_top_container, :barcode => "box2_barcode")

    acc = create(:json_accession, {
                   "instances" => [build_instance(box1), build_instance(box2)]
                 })

    unrelated_resource = create(:json_resource, {
                                  "instances" => [build_instance(box1), build_instance(box2)]
                                })


    resource = create(:json_resource)
    ao1 = create(:json_archival_object,
                 :title => "hello",
                 :instances => [build_instance(box1), build_instance(box2)],
                 :resource => {'ref' => resource.uri})

    ao2 = create(:json_archival_object,
                 :title => "world",
                 :resource => {'ref' => resource.uri},
                 :parent => {'ref' => ao1.uri})

    Resource[resource.id].transfer_to_repository(@target_repo)

    # The unrelated accession and resource should not have changed...
    Accession.to_jsonmodel(acc.id)["instances"].length.should eq(2)
    Resource.to_jsonmodel(unrelated_resource.id)["instances"].length.should eq(2)

    # and the original top containers are still intact
    TopContainer[box1.id].should_not be_nil
    TopContainer[box2.id].should_not be_nil

    # In the target repository, the instances have been moved over and point to
    # cloned versions of the top containers
    RequestContext.open(:repo_id => @target_repo.id) do
      instances = ArchivalObject.to_jsonmodel(ao1.id)["instances"]
      box1_clone = TopContainer.this_repo[:barcode => 'box1_barcode'].uri
      box2_clone = TopContainer.this_repo[:barcode => 'box2_barcode'].uri

      instances.length.should eq(2)

      instances.map {|instance| instance['sub_container']['top_container']['ref']}.should include(box1_clone)
      instances.map {|instance| instance['sub_container']['top_container']['ref']}.should include(box2_clone)
    end
  end

  it "moves linked digital objects as a part of a transfer" do
    digital_object = create(:json_digital_object)
    do_instance = build(:json_instance,
                        :instance_type => 'digital_object',
                        :digital_object => {'ref' => digital_object.uri})


    resource = create(:json_resource,
                      :instances => [do_instance])
    ao = create(:json_archival_object,
                :title => "hello again",
                :instances => [do_instance],
                :resource => {'ref' => resource.uri})

    # We won't assert on this, but let's just ensure that instances sharing a
    # digital object doesn't cause a problem.
    create(:json_archival_object,
           :title => "and another",
           :instances => [do_instance],
           :resource => {'ref' => resource.uri})

    Resource[resource.id].transfer_to_repository(@target_repo)

    RequestContext.open(:repo_id => @target_repo.id) do
      moved_digital_object = DigitalObject.this_repo[digital_object.id]

      instances = ArchivalObject.to_jsonmodel(ao.id)["instances"]
      instances.length.should eq(1)

      instances[0]['digital_object']['ref'].should eq moved_digital_object.uri
    end
  end

  it "detects when a digital object can't be moved as a part of a transfer" do
    digital_object = create(:json_digital_object)
    do_instance = build(:json_instance,
                        :instance_type => 'digital_object',
                        :digital_object => {'ref' => digital_object.uri})


    resource = create(:json_resource,
                      :instances => [do_instance])

    ao = create(:json_archival_object,
                :title => "hello again",
                :instances => [do_instance],
                :resource => {'ref' => resource.uri})

    unrelated_accession = create(:json_accession,
                                 :instances => [do_instance])

    error = nil

    begin
      Resource[resource.id].transfer_to_repository(@target_repo)
    rescue TransferConstraintError
      error = $!
    end

    error.should_not be(nil)
    error.conflicts[unrelated_accession.uri][:message].should eq('DIGITAL_OBJECT_IN_USE')
  end

  it "allows a digital object to be transferred from one repository to another" do
    digital_object = create(:json_digital_object)

    doc1 = create(:json_digital_object_component,
                  :title => "hello",
                  :digital_object => {'ref' => digital_object.uri})

    doc2 = create(:json_digital_object_component,
                  :title => "world",
                  :digital_object => {'ref' => digital_object.uri},
                  :parent => {'ref' => doc1.uri})


    DigitalObject[digital_object.id].transfer_to_repository(@target_repo)

    RequestContext.open(:repo_id => @target_repo.id) do
      tree = DigitalObject[digital_object.id].tree

      tree['children'][0]['title'].should eq('hello')
      tree['children'][0]['children'][0]['title'].should eq('world')
    end
  end

end