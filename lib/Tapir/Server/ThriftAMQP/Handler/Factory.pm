package Tapir::Server::ThriftAMQP::Handler::Factory;

use strict;
use warnings;

use Tapir::Server::ThriftAMQP::Handler::Object;
use Tapir::Server::ThriftAMQP::Handler::Inline;
use Tapir::Server::ThriftAMQP::Handler::Package;

sub new {
    my ($class, %opt) = @_;

    my $subclass = 'Tapir::Server::ThriftAMQP::Handler::';
    if ($opt{object}) {
        $subclass .= 'Object';
    }
    elsif (delete $opt{inline}) {
        $subclass .= 'Inline';
    }
    elsif (delete $opt{package}) {
        $subclass .= 'Package';
    }
    else {
        return;
    }
    return $subclass->new(%opt);
}

1;
