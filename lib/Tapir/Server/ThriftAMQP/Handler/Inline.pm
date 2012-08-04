package Tapir::Server::ThriftAMQP::Handler::Inline;

use strict;
use warnings;
use base qw(Tapir::Server::ThriftAMQP::Handler);
use Params::Validate qw(:all);

sub new {
    my $class = shift;

    my %self = validate(@_, {
        methods => { optional => 1, type => HASHREF },
        catchall => { optional => 1, type => CODEREF },
    });

    return bless \%self, $class;
}

sub add_actions {
    my ($self, $call) = @_;

    my $method_name = $call->method->name;

    my $subref = $self->{methods}{$method_name};
    $subref ||= $self->{catchall} if $self->{catchall};

    return unless $subref;

    $call->add_action($subref);
}

1;
