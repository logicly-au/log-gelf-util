use strict;
use Test::More 0.98;
use Test::Exception;
use JSON::MaybeXS qw(decode_json);

use Log::GELF::Util;

throws_ok{
    my %msg = Log::GELF::Util::encode();
}
qr/0 parameters were passed.*/,
'mandatory parameter missing';

throws_ok{
    my %msg = Log::GELF::Util::encode({});
}
qr/Mandatory parameters '(?:host|short_message)', '(?:host|short_message)' missing.*/,
'mandatory parameters missing';

my $msg;
lives_ok{
    $msg = decode_json(Log::GELF::Util::encode(
        {
            host           => 'host',
            short_message  => 'message',
        }
    ));
}
'encodes ok';

is($msg->{version}, '1.1',  'correct default version');
is($msg->{host},    'host', 'correct default version');

done_testing(5);

