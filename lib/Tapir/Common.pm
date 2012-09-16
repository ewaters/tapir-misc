package Tapir::Common;

use strict;
use warnings;
use base qw(Exporter);

our @EXPORT_OK = qw(audit_idl_document);

=head2 audit_idl_document ($thrift_idl_document)

=cut

sub audit_idl_document {
    my ($document, $audit_style) = @_;

	$audit_style ||= {
		audit_types => 1,
		warn_unused_types => 0,
		docs => {
			require => {
				return => 0,      # @return not required
				params => 0,  # @param's must match with method arguments
				methods => 1, # every method must be documented

				typedefs => 0,
				exceptions => 0,
				structs => 0,
				rest => 0,
			},

			# List the '@' keys that are flags and will have no value following them
			flags => {
				optional => 1,
				utf8     => 1,
			},
		},
	};

    my $custom_types = {};

    my (%methods_types_used);

    my @audit;
    foreach my $child (@{ $document->children }) {
        foreach my $type (_audit_flatten_types($child)) {
            next unless $type->isa('Thrift::IDL::Type::Custom');
            if ($child->isa('Thrift::IDL::Service')) {
                $methods_types_used{ $type->full_name }++;
            }
            if ($audit_style->{audit_types} && ! $custom_types->{ $type->full_name }) {
                push @audit, "$child contains reference to custom type ".$type->full_name." which hasn't yet been defined";
            }
        }

        if ($child->isa('Thrift::IDL::TypeDef')
            || $child->isa('Thrift::IDL::Struct')
            || $child->isa('Thrift::IDL::Enum')
            || $child->isa('Thrift::IDL::Senum')
        ) {
            _audit_parse_structured_comment($child, $audit_style);
            $custom_types->{ $child->full_name } = $child;
        }

        if ($audit_style->{docs}{require}{exceptions} && $child->isa('Thrift::IDL::Exception')) {
            my $failed = _audit_parse_structured_comment($child, $audit_style);
            push @audit, $failed if $failed;
        }
        elsif ($audit_style->{docs}{require}{structs} && $child->isa('Thrift::IDL::Struct') && ! $child->isa('Thrift::IDL::Exception')) {
            my $failed = _audit_parse_structured_comment($child, $audit_style);
            push @audit, $failed if $failed;
        }
        elsif ($child->isa('Thrift::IDL::Service')) {
            my $service = $child;
            _audit_parse_structured_comment($service, $audit_style);

            # Ensure that each child method has a comment that defines it's documentation,
            # and parse this comment into a data structure and store in the $method object.
            foreach my $method (@{ $child->methods }) {
                my %ids;
                foreach my $field (@{ $method->arguments }) {
                    # Check for 'optional' flag
                    if ($field->optional) {
                        push @audit, "Service $child method $method field '".$field->name."' has 'optional' flag: not valid for an argument field; rewrite as '\@optional' in comment";
                    }

                    # Check for non-duplication of field ids
                    if (! defined $ids{$field->id}) {
                        $ids{$field->id} = $field;;
                    }
                    else {
                        push @audit, "Service $child method $method field '".$field->name."' id ".$field->id." was already assigned to field '".$ids{$field->id}->name."'";
                    }
                }

                if (! $method->comments) {
                    if ($audit_style->{docs}{require}{methods}) {
                        push @audit, "Service $child method $method has no comment documentation";
                    }
                    next;
                }

                my $failed = _audit_parse_structured_comment($method, $audit_style);
                if ($failed) {
                    push @audit, $failed;
                    next;
                }
            }
        }
    }

    if ($audit_style->{warn_unused_types} && (my @unused = sort grep { ! $methods_types_used{$_} } keys %$custom_types)) {
        print STDERR "AUDIT WARN: The following types were custom defined but weren't used in any method I saw:\n";
        print STDERR "  " . join(', ', @unused) . "\n";
    }

    return @audit;
}

sub _audit_flatten_types {
    my ($node, $custom_types) = @_;
    if (! defined $node) {
        print STDERR "_audit_flatten_types() called on undef\n";
        return ();
    }
    # Resolve named custom types to their original typedef objects
    if ($node->isa('Thrift::IDL::Type::Custom') && $custom_types && $custom_types->{ $node->full_name }) {
        $node = $custom_types->{ $node->full_name };
    }
    my @types = map { $node->$_ } grep { $node->can($_) } qw(type val_type key_type returns);
    my @children = map { ref $_ ? @$_ : $_ } map { $node->$_ } grep { $node->can($_) && defined $node->$_ } qw(arguments throws children fields);
    return @types, map { _audit_flatten_types($_, $custom_types) } @types, @children;
}

sub _audit_parse_structured_comment {
    my ($object, $audit_style) = @_;

    my @comments = @{ $object->comments };

    if (! @comments) {
        return "$object has no comments";
    }

    my $comment = join "\n", map { $_->escaped_value } @comments;

    my %doc = ( param => {} );
    foreach my $line (split /\n\s*/, $comment) {
        my @parts = split /\s* (\@\w+) \s*/x, $line;
        while (defined (my $part = shift @parts)) {
            next if ! length $part;
            my ($javadoc_key) = $part =~ m{^\@(\w+)$};

            if (! $javadoc_key) {
                if (! defined $doc{description}) {
                    $doc{description} = $part;
                }
                else {
                    $doc{description} .= "\n" . $part;
                }
				next;
            }

			if ($audit_style->{docs}{flags}{$javadoc_key}) {
				$doc{$javadoc_key} = 1;
				next;
			}

			my $value = shift @parts;
			if ($javadoc_key eq 'param') {
				my ($param, $description) = $value =~ m{^(\w+) \s* (.*)$}x;
				$doc{param}{$param} = $description || '';
			}
			elsif ($javadoc_key eq 'validate') {
				my ($param, $args) = $value =~ m{^(\w+) \s* (.*)$}x;
				push @{ $doc{validate}{$param} }, $args || '';
			}
			elsif ($javadoc_key eq 'rest') {
				my ($method, $route) = split /\s+/, $value, 2;
				if ($method !~ /^(any|get|put|post|head|delete)$/i) {
					return "\@rest method '$method' is invalid";
				}
				$doc{rest} = { method => lc($method), route => $route };
			}
			else {
				push @{ $doc{$javadoc_key} }, $value;
			}
		}
    }


    # Allow fields/arguments to have structured comments and to describe themselves
    {
        # Only use arguments or fields, not both (some objects allow both)
        my @keys = grep { $object->can($_) } qw(arguments fields);
        if (@keys) {
            my $key = $keys[0];
            my @fields = @{ $object->$key };
            foreach my $field (@fields) {
                _audit_parse_structured_comment($field, $audit_style) if int @{ $field->comments };
                if ($field->{doc} && (my $description = $field->{doc}{description})) {
                    if (defined $doc{param}{$field->name}) {
                        $doc{param}{$field->name} .= '; ' . $description;
                    }
                    else {
                        $doc{param}{$field->name} = $description;
                    }
                }
            }
        }
    }

    # Check for completeness of the documentation

    if ($object->can('returns') && $audit_style->{docs}{require}{return}) {
        # Non-void return value requires description
        my $return = $object->returns;
        unless ($return->isa('Thrift::IDL::Type::Base') && $return->name eq 'void') {
            if (! $doc{return}) {
                return "$object has a non-void return value but no docs for it";
            }
        }
    }

    if ($audit_style->{docs}{require}{params}) {
        # Check the params (make a copy as I'll be destructive)
        my %params = %{ $doc{param} };
        my @fields = map { @{ $object->$_ } } grep { $object->can($_) } qw(arguments fields);
        foreach my $field (@fields) {
            if (defined $params{$field->name}) {
                delete $params{$field->name};
            }
            else {
                return "$object doesn't document argument $field";
            }
        }
        foreach my $remaining (keys %params) {
            return "$object documented param $remaining which doesn't exist in the object fields";
        }
    }

	if ($audit_style->{docs}{require}{rest} && ! $doc{rest}) {
		return "$object doesn't provide a \@rest route";
	}

    $object->{doc} = \%doc;

    return;
}

1;
