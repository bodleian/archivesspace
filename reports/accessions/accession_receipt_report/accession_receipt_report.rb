class AccessionReceiptReport < AbstractReport
  register_report

  def template
    'accession_receipt_report.erb'
  end

  def query
    db.fetch(query_string)
  end

  def query_string
    "select
      identifier as accession_number,
      title as record_title,
      accession_date as repository_date,
      container_summary,
      extent_number,
      extent_type
    from accession
      natural left outer join
        (select
          accession_id as id,
          sum(number) as extent_number,
          GROUP_CONCAT(distinct extent_type_id SEPARATOR ', ') as extent_type,
          GROUP_CONCAT(distinct extent.container_summary SEPARATOR ', ') as container_summary
        from extent
        group by accession_id) as extent_cnt
    where repo_id = #{@repo_id}"
  end

  def fix_row(row)
    ReportUtils.fix_identifier_format(row, :accession_number)
    ReportUtils.get_enum_values(row, [:extent_type])
    ReportUtils.fix_extent_format(row)
  end

  def identifier_field
    :accession_number
  end

  def page_break
    false
  end
end
