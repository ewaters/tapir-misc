#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use Data::Dumper;
use Thrift::IDL;
use Getopt::Long;
use File::Copy;
use File::Path;
use Tapir::Validator;

my $input_fn;
my $process_dir = $FindBin::Bin . '/../docs_process/';
my $project_dir = $FindBin::Bin . '/../docs_project/';
my $output_dir  = $FindBin::Bin . '/../docs/';
my $static_dir  = undef;
my $naturaldocs_bin = $FindBin::Bin . '/../NaturalDocs-1.52/NaturalDocs';
my $debug = $ENV{DEBUG};
my $audit_only = 0;

GetOptions(
    'input=s' => \$input_fn,
    'process=s' => \$process_dir,
    'project=s' => \$project_dir,
    'output=s' => \$output_dir,
    'static=s' => \$static_dir,
    'naturaldocs=s' => \$naturaldocs_bin,
    'debug' => \$debug,
    'audit_only' => \$audit_only,
);

foreach my $dir ($process_dir, $project_dir, $output_dir) {
    next if -d $dir;
    system 'mkdir', $dir;
}

my ($nd, %created_files);

## Read the document and audit it

my $document = Thrift::IDL->parse_thrift_file($input_fn, $debug);

my $validator = Tapir::Validator->new();

if (my @audit = $validator->audit_idl_document($document)) {
    print "ERROR: File didn't pass consistency check:\n";
    print "  * $_\n" foreach @audit;
    exit 1;
}

if ($audit_only) {
    print "Audit is complete\n";
    exit;
}

### Passed audit; start writing files

my %used_types;

## Generate ND for each service and method

foreach my $service (@{ $document->services }) {

    start_class('Service.' . $service->name);

    print $nd '' . ($service->{doc}{description} || '') . "\n\n";

    foreach my $method (@{ $service->methods }) {

        # Take note of all the named types that are referenced in this method
        $used_types{$_->name}++ foreach
            grep { $_->can('name') }
            $validator->_audit_flatten_types($method);

        print $nd "Function: ".$method->name."\n\n";
        print $nd $method->{doc}{description} . "\n\n";

        document_object_parameters($method, 'arguments');

        if (! $method->oneway) {
            print $nd "Returns:\n\n";
            print $nd "    " . nd_type_link($method->returns) . ($method->{doc}{return} ? '  ' . join('', @{ $method->{doc}{return} }) : '') . "\n";
            print $nd "\n";

            if (my @throws = @{ $method->throws }) {
                print $nd "Throws:\n\n";
                print $nd nd_type_link($_->type) . " (idx: " . $_->id . ")\n" foreach @throws;
                print $nd "\n";
            }
        }

    }
}

## Generate ND for my custom types

start_class('Thrift');

foreach my $type (qw(bool byte i16 i32 i64 double string binary slist void list map set)) {
    print $nd "Type: $type\n\n";
    print $nd "A Thrift built-in type.\n\n";
}

start_class('Types');

foreach my $type (
    sort { $a->name cmp $b->name }
    grep { defined $used_types{$_->name} }
    grep {
        $_->isa('Thrift::IDL::TypeDef')
        || $_->isa('Thrift::IDL::Enum')
        || $_->isa('Thrift::IDL::Constant')
        || ($_->isa('Thrift::IDL::Struct') && ! $_->isa('Thrift::IDL::Exception'))
    }
    values %{ $validator->{custom_types} }
) {
    print $nd "Type: ".$type->name."\n\n";

    if (! $type->{doc}) {
        foreach my $comment (@{ $type->comments }) {
            print $nd $comment->escaped_value . "\n\n";
        }
    }

    if ($type->isa('Thrift::IDL::TypeDef')) {
        print $nd "Base type " . nd_type_link($type->type)."\n";
    }
    elsif ($type->isa('Thrift::IDL::Enum')) {
        print $nd "Enumerated type of named values:\n";

        foreach my $value_pair (@{ $type->numbered_values }) {
            print $nd " - " . $value_pair->[0] . " (" . $value_pair->[1] . ")\n";
        }
    }
    elsif ($type->isa('Thrift::IDL::Constant')) {
        die;
    }
    elsif ($type->isa('Thrift::IDL::Struct')) {
        print $nd $type->{doc}{description} . "\n\n" if $type->{doc}{description};

        document_object_parameters($type, 'fields');
    }

    print $nd "\n";
}

print $nd "Class: Exceptions\n\n";

foreach my $exception (
    sort { $a->name cmp $b->name }
    grep { defined $used_types{$_->name} }
    grep { $_->isa('Thrift::IDL::Exception') }
    values %{ $validator->{custom_types} }
) {
    print $nd "Type: ".$exception->name."\n\n";

    print $nd $exception->{doc}{description} . "\n\n" if $exception->{doc}{description};

    document_object_parameters($exception, 'fields');

    print $nd "\n";
}

close $nd;

## Run NaturalDocs on the process directoy

if ($static_dir && -d $static_dir) {
    foreach my $file (glob "$static_dir/*") {
        my ($local) = $file =~ m{^$static_dir/(.+)$};
        my $dest_file = $process_dir . '/' . $local;
        my ($dest_dir) = $dest_file =~ m{^(.+?)/[^/]+$};
        -d $dest_dir || mkpath($dest_dir);
        copy($file, $dest_file);
        $created_files{$local}++;
    }
}

# Delete any files found in the process directory that I didn't create during this session
foreach my $process_file (glob "$process_dir/*") {
    my ($local) = $process_file =~ m{^$process_dir/(.+)$};
    next if $created_files{$local};
    unlink $process_file;
}

system $naturaldocs_bin,
    '-i' => $process_dir,
    '-o' => 'HTML' => $output_dir, 
    '-p' => $project_dir;

print "Done!  Files written to $output_dir\n";

#print Dumper([ $document->services ]);

exit;

##################################################################

sub document_object_parameters {
    my ($object, $method) = @_;

    my @fields = @{ $object->$method };
    return unless @fields;

    print $nd "Parameters:\n\n";
    foreach my $field (@fields) {
        printf $nd "    %s - %s (%s)\n",
            $field->name,
            ($object->{doc}{param}{ $field->name } || 'no docs'),
            join(', ',
                (
                    map { ($_ eq 'id' ? 'idx' : $_) . ': ' . ($_ eq 'type' ? nd_type_link($field->$_) : $field->$_) }
                    grep { defined $field->$_ }
                    qw(id type optional default_value)
                ),
                ($field->{doc} ? (
                    map { $_ . ': ' . join(' & ', @{ $field->{doc}{$_} }) }
                    grep { defined $field->{doc}{$_} }
                    qw(role)
                ) : ()),
            );
    }
    print $nd "\n";
}

sub start_class {
    my ($class) = @_;

    close $nd if $nd;

    my $local = $class . '.txt';
    my $output_fn = $process_dir . $local;
    $created_files{$local}++;

    open $nd, '>', $output_fn or die "Can't open '$output_fn' for writing: $!";
    print $nd "Class: $class\n\n";
}

sub nd_type_link {
    my ($type) = @_;

    if ($type->isa('Thrift::IDL::Type::Base')) {
        return '<Thrift.' . $type->name . '>';
    }
    elsif ($type->isa('Thrift::IDL::Type::Custom')) {
        my $obj = $validator->{custom_types}{ $type->full_name };
        die "No custom type named ".$type->full_name unless $obj;

        if ($obj->isa('Thrift::IDL::Exception')) {
            return '<Exceptions.' . $type->name . '>';
        }
        else {
            return '<Types.' . $type->name . '>';
        }
    }
    elsif ($type->can('val_type')) {
        if ($type->isa('Thrift::IDL::Type::Map')) {
            return '<Thrift.map> (' . nd_type_link($type->key_type) . ' => '. nd_type_link($type->val_type) . ')';
        }
        elsif ($type->isa('Thrift::IDL::Type::Set')) {
            return '<Thrift.set> (' . nd_type_link($type->val_type) . ')';
        }
        elsif ($type->isa('Thrift::IDL::Type::List')) {
            return '<Thrift.list> (' . nd_type_link($type->val_type) . ')';
        }
    }
    else {
        warn "Couldn't find class for type: " . Dumper($type);
        return '<' . $type . '>'; # FIXME
    }
}

