#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib (
    $FindBin::Bin . '/../lib',
);
use Tapir::JSONProxy;

Tapir::JSONProxy->run({
    http_server_port => 8080,
    ThriftIDL        => $FindBin::Bin . '/../t/thrift/calculator.thrift',
});
