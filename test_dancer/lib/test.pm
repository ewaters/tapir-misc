package test;
use Dancer ':syntax';
use Dancer::Plugin::Tapir;

our $VERSION = '0.1';

setup_thrift_handler;

get '/' => sub {
    template 'index';
};

true;
