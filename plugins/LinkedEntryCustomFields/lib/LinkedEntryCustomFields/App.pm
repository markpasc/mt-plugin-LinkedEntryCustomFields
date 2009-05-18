
package LinkedEntryCustomFields::App;
use strict;
use warnings;

use MT::Util qw( format_ts relative_date );

sub field_html_params {
    my ($field_type, $tmpl_type, $param) = @_;
    if ($param->{value}) {
        my $e = MT->model('entry')->load($param->{value});
        $param->{field_preview} = $e->title if $e;
    }
    @{$param}{qw( field_blog_id field_categories )} = split /\s*,\s*/, $param->{options}, 2;
}

sub inject_addl_field_settings {
    my ($cb, $app, $param, $tmpl) = @_;
    return 1 if $param->{type} && $param->{type} ne 'entry';

    # Inject settings template code.
    my $addl_settings = MT->component('LinkedEntryCustomFields')->load_tmpl('addl_settings.mtml');
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

sub inject_field_list_page_actions {
    my ($cb, $app, $param, $tmpl) = @_;
    return 1 if !$param->{page_actions};
    return 1 if $tmpl->text =~ m{ PageActions }xmsi;

    my $quickfilters = $tmpl->getElementById('quickfilters')
        or return 1;
    my $page_actions = $tmpl->createElement('app:PageActions');
    $tmpl->insertAfter($page_actions, $quickfilters);

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

    my %terms = ( blog_id => $blog_id );
    my %args = (
        sort      => 'authored_on',
        direction => 'descend',
    );

    if (my $cats = $app->param('cat_ids')) {
        my @cats = split /\s*,\s*/, $cats;
        $args{join} = MT::Placement->join_on('entry_id', {
            blog_id     => $blog_id,
            category_id => \@cats,
        });
    }

    my $plugin = MT->component('LinkedEntryCustomFields') or die "OMG NO COMPONENT!?!";
    my $tmpl = $plugin->load_tmpl('entry_list.mtml');
    return $app->listing({
        type => 'entry',
        template => $tmpl,
        params => {
            edit_blog_id => $blog_id,
            edit_field   => $app->param('edit_field'),
        },
        code => sub {
            my ($obj, $row) = @_;
            $row->{'status_' . lc MT::Entry::status_text($obj->status)} = 1;
            $row->{entry_permalink} = $obj->permalink
                if $obj->status == MT::Entry->RELEASE();
            if (my $ts = $obj->authored_on) {
                my $date_format = MT::App::CMS->LISTING_DATE_FORMAT();
                my $datetime_format = MT::App::CMS->LISTING_DATETIME_FORMAT();
                $row->{created_on_formatted} = format_ts($date_format, $ts, $obj->blog,
                    $app->user ? $app->user->preferred_language : undef);
                $row->{created_on_time_formatted} = format_ts($datetime_format, $ts, $obj->blog,
                    $app->user ? $app->user->preferred_language : undef);
                $row->{created_on_relative} = relative_date($ts, time, $obj->blog);
            }
            return $row;
        },
        terms => \%terms,
        args  => \%args,
        limit => 10,
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

    my $plugin = MT->component('LinkedEntryCustomFields') or die "OMG NO COMPONENT!?!";
    my $tmpl = $plugin->load_tmpl('select_entry.mtml', {
        entry_id    => $entry->id,
        entry_title => $entry->title,
        edit_field  => $edit_field,
    });
    return $tmpl;
}

sub _tags_for_field {
    my ($field) = @_;
    return if $field->type ne 'entry';
    my $tag = lc $field->tag;
    return (
        "${tag}entry" => sub {
            my ($ctx, $args, $cond) = @_;
            local $ctx->{__stash}->{field} = $field;

            # What entry are we after?
            require CustomFields::Template::ContextHandlers;
            # handlers no longer take a component as first argument in 4.25+
            my @plugin = ($MT::VERSION < 4.25) ? MT->component('commercial') : ();
            my $entry_id = CustomFields::Template::ContextHandlers::_hdlr_customfield_value(
                @plugin, @_)
                or return $ctx->_hdlr_pass_tokens_else($args, $cond);
            my $entry = MT->model('entry')->load($entry_id)
                or return $ctx->_hdlr_pass_tokens_else($args, $cond);

            local $ctx->{__stash}->{entries} = [ $entry ];
            return $ctx->_hdlr_entries($args, $cond);
        },
        "${tag}entries" => sub {
            my ($ctx, $args, $cond) = @_;
            local $ctx->{__stash}->{field} = $field;

            # What entry is this?
            my $entry = $ctx->stash('entry')
                or return $ctx->_no_entry_error();
            # So what entries are we after?
            my @entries = MT->model('entry')->search_by_meta('field.'
                . $field->basename, $entry->id);
            return $ctx->_hdlr_pass_tokens_else($args, $cond)
                if !@entries;

            local $ctx->{__stash}->{entries} = \@entries;
            return $ctx->_hdlr_entries($args, $cond);
        },
    );
}

sub load_customfield_tags {
    my $tags = eval {
        my $pack = MT->component('commercial') or return {};
        my $fields = $pack->{customfields};
        if (!$fields || !@$fields) {
            require CustomFields::Util;
            CustomFields::Util::load_meta_fields();
            $fields = $pack->{customfields};
        }
        return {} if !$fields || !@$fields;

        my %block_tags = map { _tags_for_field($_) } @$fields;
        my %tags = ( block => \%block_tags );
        \%tags;
    };
    return $tags if defined $tags;
    if (my $error = $@) {
        eval { MT->log($error) };
    }
    return {};
}

1;

