
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
        terms => {
            blog_id => $blog_id,
        },
        no_limit => 1,  # TODO: no no no
    });
}

sub select_entry {
    my $app = shift;
}

sub convert_rf2cf {
    my $app = shift;
}

1;

