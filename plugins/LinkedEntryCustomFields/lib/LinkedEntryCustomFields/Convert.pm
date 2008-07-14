
package LinkedEntryCustomFields::Convert;
use strict;
use warnings;

sub _make_custom_field {
    my %param = @_;
    my ($blog_id, $field_id, $field_data) = @param{qw( blog_id field_id data )};
    
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
}

sub _copy_custom_field_data_from_pseudofields {
    my %param = @_;
    my ($blog_id, $field_id, $datasource) = @param{qw( blog_id field_id datasource )};
    
    my $data_iter = MT->model('plugindata')->load_iter({ plugin => 'RightFieldsPseudo' });
    
    my $meta_pkg = MT->model('entry')->meta_pkg;
    # TODO: vary this based on field we're converting... really we should
    # convert pseudofields en masse, i guess, to keep from having to re-
    # iterate plugindata for every field for every blog with pseudofields.
    my $meta_field = 'vchar_idx';
    DATA: while (my $data_obj = $data_iter->()) {
        my $data = $data_obj->data;
        next DATA if !$data->{$field_id};
        my $meta_obj = $meta_pkg->new;
        $meta_obj->set_values({
            entry_id    => $data_obj->key,
            type        => "field.$field_id",
            $meta_field => $data->{$field_id},
        });
        $meta_obj->save
            or die "Could not save custom field version of field $field_id for entry #"
                . $data_obj->key . ": " . $meta_obj->errstr;
    }
    
    return 1;    
}

sub _copy_custom_field_data {
    my %param = @_;
    my ($blog_id, $field_id, $datasource) = @param{qw( blog_id field_id datasource )};
    
    return _copy_custom_field_data_from_pseudofields(@_)
        if $datasource eq '_pseudo';

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
        }) or die "Could not install properties for RightFields table class for blog #$blog_id's $field_id field: "
            . $rf_pkg->errstr;
    }

    # Copy the data for that field.
    my $meta_pkg = MT->model('entry')->meta_pkg;
    my $driver = $meta_pkg->driver;
    my $dbd = $driver->dbd;
    my $dbh = $driver->rw_handle;

    my $meta_table = $driver->table_for($meta_pkg);
    # TODO: vary the meta field based on the field we're converting
    my @meta_fields = (qw( entry_id type ), 'vchar_idx');
    @meta_fields = map { $dbd->db_column_name($meta_table, $_) } @meta_fields;

    my $rf_table = $driver->table_for($rf_pkg);
    my $id_col   = $dbd->db_column_name($rf_table, 'id');
    my $data_col = $dbd->db_column_name($rf_table, $field_id);
    
    # TODO: we should ignore fields that are already set, using INSERT IGNORE
    # on mysql or INSERT OR IGNORE on sqlite. but if we can't support it on
    # the other drivers, should we bother? should we delete conflicting data
    # first from mt_entry_meta so the insert should succeed?
    # TODO: generic multidatabase support with ORM loop?
    my $insert_sql = join q{ }, 'INSERT INTO', $meta_table,
        '(', join(q{, }, @meta_fields), ')',
        'SELECT', $id_col, q{,}, q{?}, q{,}, $data_col, 'FROM',
        $rf_table;
    $dbh->do($insert_sql, {}, "field.$field_id")
        or die $dbh->errstr || $DBI::errstr;
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
        $fields_def->key =~ m{ \A blog_(\d+) }xms or next FIELDS;
        my $blog_id = $1;
        
        my $fields_data = $fields_def->data;
        $datasource_for_blog{$blog_id} = $fields_data->{datasource};
        my $fields = $fields_data->{cols};
        FIELD: while (my ($field_id, $field_data) = each %$fields) {
            # Entry fields only.
            # TODO: less so for other field types.
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
        # TODO: vary data based on field type.
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
            _make_custom_field(
                blog_id  => $blog_id,
                field_id => $field_id,
                data     => $field_data,
            );
            
            my $datasource = $datasource_for_blog{$blog_id};
            _copy_custom_field_data(
                blog_id    => $blog_id,
                field_id   => $field_id,
                datasource => $datasource,
            );
        }
    }
    
    return $app->return_to_dashboard( redirect => 1 );
}

1;

