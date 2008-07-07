
package RightFieldsConvert::App;

sub field_html_params {
    my ($field_type, $tmpl_type, $param) = @_;
    my $e = MT->model('entry')->load($param->{value});
    $param->{preview} = $e->title if $e;
}

sub inject_addl_field_settings {
    my ($cb, $app, $param, $tmpl) = @_;
    return 1 if $param->{type} && $param->{type} ne 'entry';

    # Inject settings template code.
    my $addl_settings = MT->component('RightFieldsConvert')->load_tmpl('addl_settings.mtml');
    my $new_node = $tmpl->createElement('section');
    $new_node->innerHTML($addl_settings->text);
    $tmpl->insertAfter($new_node, $tmpl->getElementById('options'));

    # Add supporting params for our new template code.
    my ($blog_id, $options_categories) = split /\s*,\s*/, $param->{options}, 2;
    my @blogs = map { +{
        blog_id       => $_->id,
        blog_name     => $_->name,
        blog_selected => ($_->id == $blog_id ? 1 : 0)
    } } MT->model('blog')->load();
    $param->{blogs} = \@blogs;
    $param->{entry_categories} = $options_categories || q{};

    return 1;
}

sub presave_field {
    my ($cb, $app, $obj, $original) = @_;

    my $blog_id = $app->param('entry_blog') || '0';
    my $cats    = $app->param('entry_categories') || '';

    my $options = $cats ? join(q{,}, $blog_id, $cats) : $blog_id;

    for my $field ($obj, $original) {
        $field->options($options);
    }
    
    return 1;
}

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

