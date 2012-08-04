package Tapir::Server::ThriftAMQP::Handler;

use strict;
use warnings;

use Tapir::Server::ThriftAMQP::Handler::Object;
use Tapir::Server::ThriftAMQP::Handler::Inline;
use Tapir::Server::ThriftAMQP::Handler::Package;

sub factory {
    my ($class, %opt) = @_;

    my $subclass = 'Tapir::Server::ThriftAMQP::Handler::';
    if ($opt{object}) {
        $subclass .= 'Object';
    }
    elsif ($opt{inline}) {
        $subclass .= 'Inline';
    }
    elsif ($opt{package}) {
        $subclass .= 'Package';
    }
    else {
        return;
    }
    return $subclass->new(%opt);
}

sub add_actions {
    die "Override";
}

sub request_complete {
    die "Override";
}

1;
