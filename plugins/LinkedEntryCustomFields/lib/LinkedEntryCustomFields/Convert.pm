
package LinkedEntryCustomFields::Convert;
use strict;
use warnings;

use constant DEBUG => 0;

my %custom_type_for_right_type = (
    text     => 'text',
    textarea => 'textarea',
    checkbox => 'checkbox',
    date     => 'datetime',
    file     => 'asset',
    menu     => 'select',
    radio    => 'radio',
    entry    => 'entry',
);

my %field_data_for_right_type = (
    text     => [],
    textarea => [],
    checkbox => [],
    date     => [],  # cf doesn't offer any options
    file     => [ qw( filenames overwrite upload_path url_path ) ],
    menu     => [ 'choices' ],
    radio    => [ 'choices' ],
    entry    => [ qw( weblog category_ids ) ],
);

my %insert_statement_for_ddl_class = (
    'MT::ObjectDriver::DDL::mysql'  => 'INSERT IGNORE INTO',
    'MT::ObjectDriver::DDL::SQLite' => 'INSERT OR IGNORE INTO',
);

sub _meta_field_for_right_type {
    my ($type) = @_;
    my $cf = MT->registry('customfield_types')->{$type};
    return if !$cf;
    return $cf->{column_def};
}

sub _get_tag_map {
    if (my $tagmap = MT->request('lecf_tag_map')) {
        return $tagmap;
    }

    my %tag_map;
    my $tagsets = MT->registry('tags');
    TAGSET: while (my (undef, $tagset) = each %$tagsets) {
        next TAGSET if 'HASH' ne ref $tagset;  # skip component obj if any
        TAG: while (my ($tag, undef) = each %$tagset) {
            next TAG if $tag eq 'plugin';
            $tag_map{lc $tag} = 1;
        }
    }

    MT->request('lecf_tag_map', \%tag_map);
    return \%tag_map;
}

sub _make_custom_field {
    my %param = @_;
    my ($blog_id, $field_id, $field_data) = @param{qw( blog_id field_id data )};
    MT->log("Would make custom field for field $field_id but it doesn't have a type?")
        if DEBUG() && !$field_data->{type};
    my $field_type = $field_data->{type}
        or return;
    MT->log("Making custom field for field $field_id of type $field_type") if DEBUG();
    MT->log("Field $field_id type $field_type is not a supported type for conversion")
        if DEBUG() && !$custom_type_for_right_type{$field_type};
    my $cf_type = $custom_type_for_right_type{$field_type}
        or return;

    # Make or update the corresponding custom field.
    my $cf = MT->model('field')->load({
        blog_id  => ($blog_id || [ \"is null", 0 ]),
        basename => $field_id,
    });
    $cf ||= MT->model('field')->new;

    my $options;
    if ($field_type eq 'entry') {
        $options = $field_data->{weblog};
        $options = join q{,}, $field_data->{category_ids}
            if $field_data->{category_ids};
    }
    elsif ($field_type eq 'menu' || $field_type eq 'radio') {
        $options = $field_data->{choices};
        # The choices are linefeed delimited, so convert them.
        # TODO: prevent existing commas from becoming delimiters through judicious application of magic
        $options =~ s{
            \s*
            (?: = [^\r\n]* )?    # possible display value
            (?: ([\r\n]+) \s* | \z)  # linefeed or EOS
        }{ $1 ? q{,} : q{} }xmsge;
    }

    $cf->set_values({
        name     => $field_data->{label},
        obj_type => 'entry',  # rightfields only exist for entries
        type     => $cf_type,
        basename => $field_id,
    });
    $cf->options($options) if defined $options;
    $cf->blog_id($blog_id);

    my $tag = $field_data->{tag};
    if (!$tag) {
        my @possible_names = ($cf->name, $cf->basename, 'field');
        my $tagsafe_name;
        NAME: for my $name (@possible_names) {
            $tagsafe_name = MT::Util::dirify($name, q{});
            last NAME if $tagsafe_name;
        }
        $tag = join q{}, $cf->obj_type, 'data', $tagsafe_name;
    }
    $tag = lc $tag;

    # Only check uniqueness against tags if the tag is new or the tag
    # changed. Presumably we checked it last time if we saved it.
    if (!$cf->id || $tag ne $cf->tag) {
        my $tagmap = _get_tag_map();

        my $i = 0;
        my $tag_generator = sub {
            if (!$i) {
                $i = 1;
                return $tag;
            }

            $i++;  # so first is 2
            return join q{_}, substr($tag, 0, 249 - length $i), $i;
        };

        TAG: while (my $possible_tag = $tag_generator->()) {
            # We're already only checking if the tag is different from this
            # field object's tag, so don't worry about it.
            next TAG if $tagmap->{$possible_tag};
            # However we may have saved a bunch of fields this request since
            # the CF tags were generated, so check against db fields too.
            next TAG if MT->model('field')->exist({
                tag => $possible_tag,
            });

            # This tag is OK!
            $tag = $possible_tag;
            last TAG;
        }
    }

    $cf->tag($tag);

    $cf->save or die $cf->errstr;
}

sub _copy_asset_custom_fields_from_file {
    my ($self, %param) = @_;
    my ($blog_id, $field_id, $field_data, $datasource) = @param{qw( blog_id field_id data datasource )};
    MT->log("Copying values of file RF $field_id to an asset CF") if DEBUG();

    $self->progress($self->translate_escape('Converting data for file field "[_1]" to asset custom fields data...', $param{field_id}));

    my $iter;
    if ($datasource eq '_pseudo') {
        my $pdata_pkg = MT->model('plugindata');
        my $pdata_key_col = $pdata_pkg->driver->dbd->db_column_name($pdata_pkg->datasource, 'key');
        my $pdata_iter = $pdata_pkg->load_iter({
            plugin => 'RightFieldsPseudo',
        }, {
            join => MT->model('entry')->join_on(undef, {
                id      => \"= $pdata_key_col",
                blog_id => $blog_id,
            }),
        });

        $iter = sub {
            PDATA: while (my $pdata = $pdata_iter->()) {
                my $field_value = $pdata->data->{$field_id};
                MT->log('Skipping pdata #' . $pdata->id . " for field $field_id due to undefined value") if DEBUG() && !defined $field_value;
                next PDATA if !defined $field_value;
                next PDATA if !$field_value;
                return {
                    id        => $pdata->key,
                    $field_id => $field_value,
                };
            }
        };
    }
    else {
        my $rf_pkg = _make_rightfields_table_pkg(%param);
        my $rf_iter = $rf_pkg->load_iter({}, {
            join     => MT->model('entry')->join_on('id', { blog_id => $blog_id }),
            not_null => { $field_id => 1 },
        });

        $iter = sub {
            my $rf_obj = $rf_iter->()
                or return;
            return {
                id        => $rf_obj->id,
                $field_id => $rf_obj->$field_id(),
            };
        };
    }

    my $meta_pkg = MT->model('entry')->meta_pkg;
    require File::Spec;
    require File::Basename;
    while (my $file_data = $iter->()) {
        my $filepath = File::Spec->catfile($field_data->{upload_path}, $file_data->{$field_id});
        MT->log("Upload path " . $field_data->{upload_path} . " + file path data " . $file_data->{$field_id} . " = $filepath") if DEBUG();
        my ($basename, undef, $ext) = File::Basename::fileparse($filepath, qr/[A-Za-z0-9]+$/);
        MT->log("Filepath $filepath splits into $basename and $ext parts") if DEBUG();

        my $fileurl  = $field_data->{url_path};
        $fileurl .= '/' if $fileurl !~ m{ / \z }xms;
        $fileurl .= $file_data->{$field_id};

        my $asset_class = MT->model('asset')->handler_for_file($filepath);
        my $asset = $asset_class->load({
            file_path => $filepath,
            blog_id   => $blog_id,
        });
        $asset ||= $asset_class->new;

        $asset->set_values({
            blog_id   => $blog_id,
            file_path => $filepath,
            file_name => $basename . $ext,
            file_ext  => $ext,
            url       => $fileurl,
        });
        $asset->save or die $asset->errstr;

        my $meta_obj = $meta_pkg->new;
        $meta_obj->set_values({
            entry_id  => $file_data->{id},
            type      => "field.$field_id",
            vclob     => $asset->as_html(),
        });
        $meta_obj->save
            or die "Could not save custom field version of field $field_id for entry #"
                . $file_data->{id} . ": " . $meta_obj->errstr;
    }

    return 0;
}

sub _copy_custom_field_data_from_pseudofields {
    my ($self, %param) = @_;
    my ($blog_id, $field_id, $field_data, $datasource) = @param{qw( blog_id field_id data datasource )};
    my $field_type = $field_data->{type};

    $self->progress($self->translate_escape('Converting data for field "[_1]" from plugindata to custom fields data...', $param{field_id}));

    my $data_iter = MT->model('plugindata')->load_iter({ plugin => 'RightFieldsPseudo' });

    my $meta_pkg = MT->model('entry')->meta_pkg;
    # TODO: really we should convert pseudofields en masse, i guess, to keep
    # from having to reiterate plugindata for every field for every blog.
    my $cf_type = $custom_type_for_right_type{$field_type}
        or die "Can't convert custom field data from unknown type $field_type\n";
    my $meta_field = _meta_field_for_right_type($cf_type);
    DATA: while (my $data_obj = $data_iter->()) {
        my $data = $data_obj->data;
        next DATA if !$data->{$field_id};
        my $meta_obj = $meta_pkg->new;
        # TODO: if this is a choice field, convert keys of key=value choice pairs into values
        my $value = $data->{$field_id};
        if ($field_type eq 'radio' || $field_type eq 'menu') {
            $value =~ s{ \A \s+ | \s+ \z }{}xmsg;
        }
        $meta_obj->set_values({
            entry_id    => $data_obj->key,
            type        => "field.$field_id",
            $meta_field => $value,
        });
        $meta_obj->save
            or die "Could not save custom field version of field $field_id for entry #"
                . $data_obj->key . ": " . $meta_obj->errstr;
    }

    return 0;
}

sub _make_rightfields_table_pkg {
    my %param = @_;
    my ($blog_id, $field_id, $datasource) = @param{qw( blog_id field_id datasource )};

    # Find the class that represents that RF table.
    my $rf_pkg = join q{::}, 'RightFieldsTable', $field_id, "Blog$blog_id";
    if (!eval { $rf_pkg->properties }) {
        # Guess we have to make it.
        eval "package $rf_pkg; use base qw( MT::Object ); 1"
            or die "Could not create RightFields table class for blog #$blog_id's $field_id field: $@";

        $rf_pkg->install_properties({
            datasource => $datasource,
            column_defs => {
                id        => 'integer not null',
                $field_id => 'integer',  # for linked entries
            },
            indexes => {
                id => 1,
            },
            primary_key => 'id',
        }) or die "Could not install properties for RightFields table class for blog #$blog_id's $field_id field: "
            . $rf_pkg->errstr;
    }

    return $rf_pkg;
}

sub step_convert_data {
    my ($self, %param) = @_;
    return 0 if !%param;  # nothing to convert?
    my ($blog_id, $field_id, $field_data, $datasource) = @param{qw( blog_id field_id data datasource )};
    my $field_type = $field_data->{type};

    return _copy_asset_custom_fields_from_file($self, %param)
        if $field_type eq 'file';
    # TODO: if this is a choice field, convert keys of key=value choice pairs
    # into values... by converting them loopily. or something.
    return _copy_custom_field_data_from_pseudofields($self, %param)
        if $datasource eq '_pseudo';

    $self->progress($self->translate_escape('Converting data for field "[_1]" to custom fields data...', $param{field_id}));

    my $rf_pkg = _make_rightfields_table_pkg(%param);

    # Copy the data for that field.
    my $meta_pkg = MT->model('entry')->meta_pkg;
    my $driver = $meta_pkg->driver;
    my $dbd = $driver->dbd;
    my $dbh = $driver->rw_handle;

    my $meta_table = $driver->table_for($meta_pkg);
    my $cf_type = $custom_type_for_right_type{$field_type};
    my @meta_fields = (qw( entry_id type ), _meta_field_for_right_type($cf_type));
    @meta_fields = map { $dbd->db_column_name($meta_table, $_) } @meta_fields;

    my $rf_table = $driver->table_for($rf_pkg);
    my $id_col   = $dbd->db_column_name($rf_table, 'id');
    my $data_col = $dbd->db_column_name($rf_table, $field_id);

    my $trim_data = $field_type eq 'radio' ? 1
                  : $field_type eq 'menu'  ? 1
                  :                          0
                  ;

    # TODO: should we instead delete conflicting data from mt_entry_meta so
    # an INSERT without IGNORE should succeed?
    # TODO: generic multidatabase support with ORM loop?
    my $insert_stmt = $insert_statement_for_ddl_class{ $dbd->ddl_class }
        || 'INSERT INTO';  # we'll have to error if we can't ignore conflicts
    my $insert_sql = join q{ }, $insert_stmt, $meta_table,
        '(', join(q{, }, @meta_fields), ')',
        'SELECT', $id_col, q{,}, q{?}, q{,},
        ($trim_data ? ('TRIM(', $data_col, ')') : ($data_col)),
        'FROM', $rf_table;
    $dbh->do($insert_sql, {}, "field.$field_id")
        or die $dbh->errstr || $DBI::errstr;

    return 0;
}

sub step_convert_fields {
    my ($self, %param) = @_;

    # Look for RF field definitions.
    my $def_iter = MT->model('plugindata')->load_iter({ plugin => 'rightfields' });

    $self->progress($self->translate_escape('Discovering RightFields settings...'));

    my (@tags, @fields);
    DEF: while (my $def = $def_iter->()) {
        # Don't care about default settings, only the ones actually in use on blogs.
        next DEF if $def->key !~ m{ \A blog_ }xms;
        push @tags,   $def->clone if $def->key =~ m{ _tags \z }xms;
        push @fields, $def->clone if $def->key =~ m{ _extra \z }xms;
    }

    $self->progress($self->translate_escape('Cataloguing RightFields tags...'));

    my %tags_for_fields;
    TAG: for my $tag_def (@tags) {
        $tag_def->key =~ m{ \A blog_(\d+) }xms
            or next TAG;
        my $blog_id = $1;

        # We don't know from the tag data what fields are entries, so record all of them.
        my $tags_data = $tag_def->data;
        for my $tag_data (@$tags_data) {
            my ($field, $tag_name) = @{$tag_data}{qw( field tag )};

            # Each CF can have only one tag, and we'll need to pull them out by field.
            $tags_for_fields{$blog_id}->{$field} = $tag_name;
        }
    }

    $self->progress($self->translate_escape('Cataloguing RightFields fields...'));

    my (%fields_for_blog, %fields_by_id, %datasource_for_blog);
    FIELDS: for my $fields_def (@fields) {
        $fields_def->key =~ m{ \A blog_(\d+) }xms or next FIELDS;
        my $blog_id = $1;

        my $fields_data = $fields_def->data;
        $datasource_for_blog{$blog_id} = $fields_data->{datasource};
        my $fields = $fields_data->{cols};
        FIELD: while (my ($field_id, $field_data) = each %$fields) {
            # TODO: less so for other field types.
            my $field_type = $field_data->{type} or next FIELD;
            next FIELD if !$custom_type_for_right_type{$field_type};

            my %field;
            my $field_keys = $field_data_for_right_type{$field_type}
                or next FIELD;
            $field{$_} = $field_data->{$_} for qw( label type ), @$field_keys;
            $field{blog_id} = $blog_id;
            $field{tag} = $tags_for_fields{$blog_id}->{$field_id};

            $fields_for_blog{$blog_id} ->{$field_id} = \%field;
            $fields_by_id   {$field_id}->{$blog_id}  = \%field;
        }
    }

    $self->progress($self->translate_escape('Converting RightFields fields to custom fields...'));

    # Upgrade duplicates to global fields.
    FIELD_BY_ID: while (my ($field_id, $fields) = each %fields_by_id) {
        my $make_global = 1;

        my ($first_field, @fields) = values %$fields;
        if (!@fields) {
            # Leave fields in only one blog in only one blog.
            $make_global = 0;
        }
        elsif ($first_field->{type} eq 'file') {
            # There's no such thing as a system-wide asset custom field.
            $make_global = 0;
        }
        else {
            # Compare the fields across all the important axes to see if they differ.
            my @data = qw( type tag );
            my $type = $first_field->{type};
            push @data, @{ $field_data_for_right_type{$type} || [] };
            DATUM: for my $datum (@data) {
                my $first_value = $first_field->{$datum};
                $first_value = lc $first_value if $datum eq 'label';
                for my $next_field (@fields) {
                    my $next_value = $next_field->{$datum};
                    $next_value = lc $next_value if $datum eq 'label';
                    $make_global &&=  defined $first_value && !defined $next_value        ? 0
                                   : !defined $first_value &&  defined $next_value        ? 0
                                   :  defined $first_value && $first_value ne $next_value ? 0
                                   :                                                        1
                                   ;
                    if (!$make_global) {
                        my $app = MT->instance;
                        my $pl = MT->component('LinkedEntryCustomFields');
                        $app->log({
                            message => $pl->translate(
                                'Duplicating [_1] field across blogs: fields are different in their [_2]',
                                $first_field->{label},
                                $datum,
                            ),
                            level    => MT::Log->INFO(),
                            class    => 'system',
                            category => 'upgrade',
                        });
                        last DATUM;
                    }
                }
            }
        }

        if ($make_global) {
            # Give the global field the most common label.
            my %label_usage;
            for my $field (values %$fields) {
                $label_usage{ $field->{label} }++;
            }
            my ($common_label) = sort {
                $label_usage{$b} <=> $label_usage{$a} } keys %label_usage;
            local $first_field->{label} = $common_label;

            _make_custom_field(
                blog_id  => 0,
                field_id => $field_id,
                data     => $first_field,
            );
            next FIELD_BY_ID;
        }

        while (my ($blog_id, $field_data) = each %$fields) {
            _make_custom_field(
                blog_id    => $blog_id,
                field_id   => $field_id,
                data       => $field_data,
            );
        }
    }

    # Make corresponding custom fields.
    while (my ($blog_id, $fields) = each %fields_for_blog) {
        my $datasource = $datasource_for_blog{$blog_id};
        while (my ($field_id, $field_data) = each %$fields) {
            $self->add_step('rf2cf_convert_data',
                blog_id    => $blog_id,
                field_id   => $field_id,
                data       => $field_data,
                datasource => $datasource,
            );
        }
    }

    return 0;  # done
}

1;

