
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

sub convert_rf2cf {
    my $app = shift;
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
            my $entry_id = CustomFields::Template::ContextHandlers::_hdlr_customfield_value(
                MT->component('commercial'), @_)
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

sub convert_rf2cf {
    my $app = shift;

    # Look for RF field definitions.
    my $def_iter = MT->model('plugindata')->load_iter({ plugin => 'rightfields' });
    
    my (@tags, @fields);
    DEF: while (my $def = $def_iter->()) {
        # Don't care about default settings, only the ones actually in use on blogs.
        next DEF if $def->key !~ m{ \A blog_ }xms;
        push @tags,   $def->clone if $def->key =~ m{ _tags \z }xms;
        push @fields, $def->clone if $def->key =~ m{ _extra \z }xms;
    }

    my %tags_for_fields;
    TAG: for my $tag_def (@tags) {
        MT->log('OH HAI from tag ' . $tag_def->key);
        $tag_def->key =~ m{ \A blog_(\d+) }xms or next TAG;
        my $blog_id = $1;

        # We don't know from the tag data what fields are entries, so record all of them.
        my $tags_data = $tag_def->data;
        for my $tag_data (@$tags_data) {
            my ($field, $tag_name) = @{$tag_data}{qw( field tag )};

            # Each CF can have only one tag, and we'll need to pull them out by field.
            $tags_for_fields{$blog_id}->{$field} = $tag_name;
        }
    }
    
    my (%fields_for_blog, %fields_by_id, %datasource_for_blog);
    FIELDS: for my $fields_def (@fields) {
        MT->log('OH HAI from fieldset ' . $fields_def->key);
        $fields_def->key =~ m{ \A blog_(\d+) }xms or next FIELDS;
        my $blog_id = $1;
        
        my $fields_data = $fields_def->data;
        $datasource_for_blog{$blog_id} = $fields_data->{datasource};
        my $fields = $fields_data->{cols};
        FIELD: while (my ($field_id, $field_data) = each %$fields) {
            # Entry fields only.
            next FIELD if !$field_data->{type}
                || $field_data->{type} ne 'entry';

            my %field;
            $field{$_} = $field_data->{$_} for qw( label weblog category_ids );
            $field{blog_id} = $blog_id;
            $field{tag} = $tags_for_fields{$blog_id}->{$field_id};
            
            $fields_for_blog{$blog_id} ->{$field_id} = \%field;
            $fields_by_id   {$field_id}->{$blog_id}  = \%field;
        }
    }
    
    # Upgrade duplicates to global fields.
    FIELD_BY_ID: while (my ($field_id, $fields) = each %fields_by_id) {
        # Leave fields that are only in one blog alone.
        next FIELD_BY_ID if 1 == scalar keys %$fields;
        
        my ($first_field, @fields) = values %$fields;
        for my $datum (qw( label weblog category_ids tag )) {
            my $first_value = $first_field->{$datum};
            for my $next_field (@fields) {
                my $next_value = $next_field->{$datum};
                next FIELD_BY_ID if  defined $first_value && !defined $next_value;
                next FIELD_BY_ID if !defined $first_value &&  defined $next_value;
                next FIELD_BY_ID if  defined $first_value
                    && $first_value ne $next_value;
            }
        }
        
        # Huh, everything matched. Make this a global field.
        # TODO: Delete the value from each of their %fields_by_blog groups, using blog_id member.
        # TODO: Assign first_field to blog_id=0 group. Or have a separate set of global fields?
    }
    
    # Make corresponding custom fields.
    while (my ($blog_id, $fields) = each %fields_for_blog) {
        while (my ($field_id, $field_data) = each %$fields) {
            # Make or update the corresponding custom field.
            my $cf = MT->model('field')->load({
                blog_id  => $blog_id,
                basename => $field_id,
            });
            $cf ||= MT->model('field')->new;
            
            my $options = $field_data->{weblog};
            $options = join q{,}, $field_data->{category_ids}
                if $field_data->{category_ids};

            $cf->set_values({
                name     => $field_data->{label},
                obj_type => 'entry',
                type     => 'entry',
                options  => $options,
                basename => $field_id,
            });
            $cf->blog_id($blog_id) if $blog_id;  # TODO: 0 = global?

            my $tag = $field_data->{tag};
            $tag ||= lc join q{}, $cf->obj_type, 'data', $cf->name;
            # TODO: ensure the tag is unique, since CF makes us.
            $cf->tag($tag);

            $cf->save or die $cf->errstr;
            
            # Copy the data for that field.
            my $datasource = $datasource_for_blog{$blog_id};
            if ($datasource eq '_pseudo') {
                # omg pseudo objects aiee
            }
            else {
                my $sql = MT::ObjectDriver::SQL->new;
                $sql->
            }
        }
    }
    
    # Start copying data.
    
    
    return $app->return_to_dashboard( redirect => 1 );
}

1;

