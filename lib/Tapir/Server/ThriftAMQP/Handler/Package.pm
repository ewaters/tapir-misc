package Tapir::Server::ThriftAMQP::Handler::Package;

use strict;
use warnings;
use base qw(Tapir::Server::ThriftAMQP::Handler);
use Params::Validate qw(:all);

sub new {
    my $class = shift;

    my %self = validate(@_, {
        methods => { type => ARRAYREF },
    });

    return bless \%self, $class;
}

1;
