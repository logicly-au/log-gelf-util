use strict;
use Test::More 0.98;
use Test::Exception;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use IO::Uncompress::Inflate qw(inflate $InflateError) ;
use JSON::MaybeXS qw(decode_json);

use Log::GELF::Util;

throws_ok{
    my %msg = Log::GELF::Util::compress();
}
qr/0 parameters were passed.*/,
'mandatory parameter missing';

throws_ok{
    Log::GELF::Util::compress({});
}
qr/Parameter #1.*/,
'message parameters wrong type';

throws_ok{
    my %msg = Log::GELF::Util::compress(1,'wrong');
}
qr/Parameter #2.*/,
'type parameters wrong';

throws_ok{
    my %msg = Log::GELF::Util::uncompress();
}
qr/0 parameters were passed.*/,
'mandatory parameter missing';

throws_ok{
    my %msg = Log::GELF::Util::uncompress(
       {},
    );
}
qr/Parameter #1.*/,
'message parameters wrong type';

lives_ok{
    Log::GELF::Util::compress( 1, 'gzip');
}
'gzips explicit ok';

lives_ok{
    Log::GELF::Util::compress( 1, 'zlib');
}
'zlib explicit ok';

my $msgz;
lives_ok{
    $msgz = Log::GELF::Util::compress(
        Log::GELF::Util::encode(
            {
                host           => 'host',
                short_message  => 'message',
            }
        )
    );
}
'gzips ok';

my $msgj;
gunzip \$msgz => \$msgj
  or die "gunzip failed: $GunzipError";
my $msg = decode_json($msgj);

is($msg->{version}, '1.1',  'correct default version');
is($msg->{host},    'host', 'correct default version');

lives_ok{
    $msg = decode_json(
        Log::GELF::Util::uncompress($msgz)
    );
}
'uncompresses gzip ok';

is($msg->{version}, '1.1',  'correct default version');
is($msg->{host},    'host', 'correct default version');

my $msgz;
lives_ok{
    $msgz = Log::GELF::Util::compress(
     Log::GELF::Util::encode(
            {
                host           => 'host',
                short_message  => 'message',
            }
        ),
        'zlib',
    );
}
'deflates ok';

my $msgj;
inflate \$msgz => \$msgj
  or die "inflate failed: $InflateError";
my $msg = decode_json($msgj);

is($msg->{version}, '1.1',  'correct default version');
is($msg->{host},    'host', 'correct default version');

lives_ok{
    $msg = decode_json(
        Log::GELF::Util::uncompress($msgz)
    );
}
'uncompresses zlib ok';

is($msg->{version}, '1.1',  'correct default version');
is($msg->{host},    'host', 'correct default version');

done_testing(19);

