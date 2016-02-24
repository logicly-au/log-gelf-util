use strict;
use warnings;

use Test::More;
use Test::Exception;

use Log::GELF::Util qw(
    decode_chunk
    compress
    uncompress
    is_chunked
    enchunk
    dechunk
    decode_chunk
    encode
    $GELF_MSG_MAGIC
);

use JSON::MaybeXS qw(decode_json);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use IO::Uncompress::Inflate qw(inflate $InflateError);

sub test_dechunk {

    my @chunks;
    my $msg;

    do {
        $msg = dechunk(\@chunks, decode_chunk(shift()));
    } until ($msg);

    return uncompress( $msg );
};

throws_ok{
    is_chunked();
}
qr/0 parameters were passed.*/,
'mandatory parameters missing';

ok( ! is_chunked( 'no magic' ), 'no magic' );

ok( is_chunked( $GELF_MSG_MAGIC ), 'magic' );

throws_ok{
   enchunk();
}
qr/0 parameters were passed to Log::GELF::Util::enchunk but 2 were expected/,
'mandatory parameters missing';

throws_ok{
    enchunk('0123456789', -1);
}
qr/chunk size must be "lan", "wan", a positve integer, or 0 \(no chunking\)/,
'enchunk negative size';

throws_ok{
    enchunk('0123456789', 'xxx');
}
qr/chunk size must be "lan", "wan", a positve integer, or 0 \(no chunking\)/,
'enchunk bad size';

my @chunks;
lives_ok{
    @chunks = enchunk('0123456789');
}
'enchunks ok - size default';

lives_ok{
    @chunks = enchunk('0123456789', 0);
}
'enchunks ok - 0';
is(scalar @chunks, 1, 'correct number of chunks - 0');

lives_ok{
    @chunks = enchunk('0123456789', 1);
}
'enchunks ok - 1';
is(scalar @chunks, 10, 'correct number of chunks -  1');

lives_ok{
    @chunks = enchunk(
        encode(
            {
                host           => 'host',
                short_message  => 'message',
            }
        ),
        4
    );
}
'enchunks ok - message';

throws_ok{
    decode_chunk();
}
qr/0 parameters were passed.*/,
'mandatory parameter to decode_chunk missing';

my $chunk;
lives_ok{
    $chunk = decode_chunk($chunks[0]);
}
'decode chunk succeeds';

ok($chunk->{id},                              'id exists');
is($chunk->{sequence_number}, 0,              'sequence correct');
is($chunk->{sequence_count},  scalar @chunks, 'sequence correct');
is(length($chunk->{data}),    4,              'chunk size correct');

my $msg = decode_json(test_dechunk(@chunks));
is($msg->{version}, '1.1',  'correct default version');
is($msg->{host},    'host', 'correct default version');

lives_ok{
    @chunks = enchunk(
        compress(
            encode(
                {
                    host           => 'host',
                    short_message  => 'message',
                }
            )
        ),
        4
    );
}
'enchunks compressed gzip ok';

$msg = decode_json(test_dechunk(@chunks));
is($msg->{version}, '1.1',  'correct default version');
is($msg->{host},    'host', 'correct default version');

lives_ok{
    @chunks = enchunk(
        compress(
            encode(
                {
                    host           => 'host',
                    short_message  => 'message',
                }
            ),
            'zlib',
        ),
        4
    );
}
'enchunks compressed zlib ok';

$msg = decode_json(test_dechunk(@chunks));
is($msg->{version}, '1.1',  'correct default version');
is($msg->{host},    'host', 'correct default version');

done_testing(26);

