(function(exports) {

    function SimpleRenderer(should_link_to_record) {
        this.endpointMarkerTemplate = $('<tr class="end-marker" />');

        this.should_link_to_record = should_link_to_record || false;

        this.rootTemplate = $('<tr> ' +
            '  <td class="no-drag-handle"></td>' +
            '  <td class="title"></td>' +
            '</tr>');


        this.nodeTemplate = $('<tr> ' +
            '  <td class="drag-handle"></td>' +
            '  <td class="title"><span class="indentor"><button class="expandme"><i class="expandme-icon glyphicon glyphicon-chevron-right" /></button></span> </td>' +
            '</tr>');
    }


    SimpleRenderer.prototype.endpoint_marker = function () {
        return this.endpointMarkerTemplate.clone(true);
    }


    SimpleRenderer.prototype.get_root_template = function () {
        return this.rootTemplate.clone(false);
    }


    SimpleRenderer.prototype.get_node_template = function () {
        return this.nodeTemplate.clone(false);
    };


    SimpleRenderer.prototype.add_root_columns = function (row, rootNode) {
        var $link = row.find('a.record-title');

        if (this.should_link_to_record) {
            $link.attr('href', rootNode.uri);
        }

        $link.html(rootNode.parsed_title);
    }


    SimpleRenderer.prototype.add_node_columns = function (row, node) {
        var $link = row.find('a.record-title');
        var title = this.build_node_title(node);

        if (this.should_link_to_record) {
            $link.attr('href', node.uri);
        }

        $link.html(title);
    };


    SimpleRenderer.prototype.build_node_title = function (node) {
        var title_bits = [];
        if (node.parsed_title) {
            title_bits.push(node.parsed_title);
        }

        if (node.label) {
            title_bits.push(node.label);
        }

        if (node.dates && node.dates.length > 0) {
            var first_date = node.dates[0];
            if (first_date.expression) {
                title_bits.push(first_date.expression);
            } else if (first_date.begin && first_date.end) {
                title_bits.push(first_date.begin + '-' + first_date.end);
            } else if (first_date.begin) {
                title_bits.push(first_date.begin);
            }
        }

        return title_bits.join(', ');
    }

    exports.SimpleRenderer = SimpleRenderer;
})(window);