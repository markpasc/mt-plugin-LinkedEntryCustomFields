
package RightFieldsConvert::App;

sub list_entry_mini {
    my $app = shift;

    my $blog_id = $app->param('blog_id')
        or return $app->errtrans('No blog_id');
    my $entry_iter = MT->model('entry')->load_iter({
        blog_id => $blog_id,
    });

    my $plugin = MT->component('RightFieldsConvert') or die "OMG NO COMPONENT!?!";
    my $tmpl = $plugin->load_tmpl('entry_list.mtml');
    return $app->listing({
        type => 'entry',
        template => $tmpl,
        params => {
            edit_blog_id => $blog_id,
            edit_field   => $app->param('edit_field'),
        },
        terms => {
            blog_id => $blog_id,
        },
        no_limit => 1,  # TODO: no no no
    });
}

sub select_entry {
    my $app = shift;

    my $entry_id = $app->param('id')
        or return $app->errtrans('No id');
    my $entry = MT->model('entry')->load($entry_id)
        or return $app->errtrans('No entry #[_1]', $entry_id);
    my $edit_field = $app->param('edit_field')
        or return $app->errtrans('No edit_field');

    my $plugin = MT->component('RightFieldsConvert') or die "OMG NO COMPONENT!?!";
    my $tmpl = $plugin->load_tmpl('select_entry.mtml', {
        entry_id    => $entry->id,
        entry_title => $entry->title,
        edit_field  => $edit_field,
    });
    return $tmpl;
}

sub convert_rf2cf {
    my $app = shift;
}

1;

