use strict;
use warnings;

use Test::More;
use Test::Exception;

use Log::GELF::Util;

use JSON::MaybeXS qw(decode_json);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use IO::Uncompress::Inflate qw(inflate $InflateError);

my $GELF_MSG_MAGIC     = pack('C*', 0x1e, 0x0f);

sub test_dechunk {
    
    my $last_msg_id;
    my $msg;

    foreach my $chunk (@_) {

        my $chunk = Log::GELF::Util::decode_chunk( $chunk );

        die "sequence_number > sequence count - should not happen"
            if $chunk->{sequence_number} > $chunk->{sequence_count};

        die "message_id <> last message_id - should not happen"
            if defined $last_msg_id && $last_msg_id ne $chunk->{id};

        $last_msg_id = $chunk->{id};
        
        $msg .= $chunk->{data};
    }
    
    return Log::GELF::Util::uncompress( $msg );
};

throws_ok{
    my %msg = Log::GELF::Util::is_chunked();
}
qr/0 parameters were passed.*/,
'mandatory parameters missing';

ok( ! Log::GELF::Util::is_chunked( 'no magic' ), 'no magic' );

ok( Log::GELF::Util::is_chunked( $GELF_MSG_MAGIC ), 'magic' );

throws_ok{
    my %msg = Log::GELF::Util::enchunk();
}
qr/0 parameters were passed.*/,
'mandatory parameters missing';

my @chunks;
lives_ok{
    @chunks = Log::GELF::Util::enchunk(
        Log::GELF::Util::encode(
            {
                host           => 'host',
                short_message  => 'message',
            }
        ),
        4
    );
}
'enchunks ok';

throws_ok{
    Log::GELF::Util::decode_chunk();
}
qr/0 parameters were passed.*/,
'mandatory parameter to decode_chunk missing';

my $chunk;
lives_ok{
    $chunk = Log::GELF::Util::decode_chunk($chunks[0]);
}
'decode chunk succeeds';

ok($chunk->{id}, 'id exists');
is($chunk->{sequence_number}, 0,              'sequence correct');
is($chunk->{sequence_count},  scalar @chunks, 'sequence correct');
is(length($chunk->{data}),    4,              'chunk size correct');

my $msg = decode_json(test_dechunk(@chunks));
is($msg->{version}, '1.1',  'correct default version');
is($msg->{host},    'host', 'correct default version');

lives_ok{
    @chunks = Log::GELF::Util::enchunk(
        Log::GELF::Util::compress(
            Log::GELF::Util::encode(
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
    @chunks = Log::GELF::Util::enchunk(
        Log::GELF::Util::compress(
            Log::GELF::Util::encode(
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

done_testing(19);

