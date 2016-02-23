package Log::GELF::Util;
use 5.010;
use strict;
use warnings;

require Exporter;
use Readonly;

our (
    $VERSION,
    @ISA,
    @EXPORT_OK, 
    %EXPORT_TAGS,
    $GELF_MSG_MAGIC,
    $ZLIB_MAGIC,
    $GZIP_MAGIC,
    %LEVEL_NAME_TO_NUMBER,
    %LEVEL_NUMBER_TO_NAME,
    %GELF_MESSAGE_FIELDS,
    $LEVEL_NAME_REGEX,
);

$VERSION = "0.01";
Readonly $VERSION;

use Params::Validate qw(
    validate
    validate_pos
    validate_with
    SCALAR
    ARRAYREF
    HASHREF
);
use Time::HiRes qw(time);
use Sys::Syslog qw(:macros);
use JSON::MaybeXS qw(encode_json decode_json);
use IO::Compress::Gzip qw(gzip $GzipError);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use IO::Compress::Deflate qw(deflate $DeflateError);
use IO::Uncompress::Inflate qw(inflate $InflateError);
use Math::Random::MT qw(irand);

Readonly $GELF_MSG_MAGIC => pack('C*', 0x1e, 0x0f);
Readonly $ZLIB_MAGIC     => pack('C*', 0x78, 0x9c);
Readonly $GZIP_MAGIC     => pack('C*', 0x1f, 0x8b);

Readonly %LEVEL_NAME_TO_NUMBER => (
    emerg  => LOG_EMERG,
    alert  => LOG_ALERT,
    crit   => LOG_CRIT,
    err    => LOG_ERR,
    warn   => LOG_WARNING,
    notice => LOG_NOTICE,
    info   => LOG_INFO,
    debug  => LOG_DEBUG,
);

Readonly %LEVEL_NUMBER_TO_NAME => (
    LOG_EMERG   =>  'emerg',
    LOG_ALERT   =>  'alert',
    LOG_CRIT    =>  'crit',
    LOG_ERR     =>  'err',
    LOG_WARNING =>  'warn',
    LOG_NOTICE  =>  'notice',
    LOG_INFO    =>  'info',
    LOG_DEBUG   =>  'debug',
);

Readonly %GELF_MESSAGE_FIELDS => (
    version        => 1,
    host           => 1,
    short_message  => 1,
    full_message   => 1,
    timestamp      => 1,
    level          => 1,
    facility       => 1,
    file           => 1,
);

my $ln = '^(' .
    (join '|', (keys %LEVEL_NAME_TO_NUMBER)) .
    ')\w*$';
$LEVEL_NAME_REGEX = qr/$ln/i;
undef $ln;

@ISA       = qw(Exporter);
@EXPORT_OK = qw( 
    $GELF_MSG_MAGIC
    $ZLIB_MAGIC
    $GZIP_MAGIC
    %LEVEL_NAME_TO_NUMBER
    %LEVEL_NUMBER_TO_NAME
    %GELF_MESSAGE_FIELDS
    validate_message
    encode
    decode
    compress
    uncompress
    enchunk
    is_chunked
    decode_chunk
    parse_level
    parse_size
);

push @{ $EXPORT_TAGS{all} }, @EXPORT_OK ;
Exporter::export_ok_tags('all');

sub validate_message {
    my %p = validate_with(
        params      => \@_,
        allow_extra => 1,
        spec        => {
            version       => {
                default => '1.1',
                callbacks => {
                    version_check => sub {
                        my $version = shift;
                        $version =~ /^1\.1$/
                            or die 'version must be 1.1, supplied $version';
                    },
                },
            },
            host          => { type => SCALAR },
            short_message => { type => SCALAR },
            full_message  => { type => SCALAR, optional => 1 },
            timestamp     => { type => SCALAR, default  => time },
            level         => { type => SCALAR, default  => 1 },
            facility      => {
                optional  => 1,
                callbacks => {
                    facility_check => sub {
                        my $facility = shift;
                        $facility =~ /^\d+$/
                            or die 'facility must be a positive integer';
                    },
                    deprecated => sub { warn "facility is deprecated, send as additional field instead" },
                },
            },
            file          => {
                optional  => 1,
                type      => SCALAR,
                callbacks => {
                    deprecated => sub { warn "file is deprecated, send as additional field instead" },
                },
            },
        },
    );

    $p{level} = parse_level($p{level});

    foreach my $key (keys %p ) {
        if ( $key eq '_id' ||
             ! ( exists $GELF_MESSAGE_FIELDS{$key} || $key =~ /^_/ )
        ) {
               die "invalid field '$key'";
        }
    }
    
    return \%p;
}

sub encode {
    my @p = validate_pos(
        @_,
        { type => HASHREF },
    );

    return encode_json(validate_message(@p));
}

sub decode {
    my @p = validate_pos(
        @_,
        { type => SCALAR },
    );

    my $msg = shift @p;

    return validate_message(decode_json($msg));
}

sub compress {
    my @p = validate_pos(
        @_,
        { type  => SCALAR },
        {
            default => 'gzip',
            callbacks => {
                compress_type => sub {
                    my $level = shift;
                    $level =~ /^(?:zlib|gzip)$/
                        or die 'compression type must be gzip (default) or zlib';
                },
            },
        },
    );

    my ($message, $type) = @p;
    
    my $method = \&gzip;
    my $error  = \$GzipError;
    if ( $type eq 'zlib' ) {
        $method = \&deflate;
        $error  = \$DeflateError;
    }

    my $msgz;
    &{$method}(\$message => \$msgz)
      or die "compress failed: ${$error}";

    return $msgz;
}

sub uncompress {
    my @p = validate_pos(
        @_,
        { type => SCALAR }
    );
    
    my $message = shift @p;
    
    my $msg_magic = substr $message, 0, 2;
    
    my $method;
    my $error;
    if ($ZLIB_MAGIC eq $msg_magic) {
        $method = \&inflate;
        $error  = \$InflateError;
    }
    elsif ($GZIP_MAGIC eq $msg_magic) {
        $method = \&gunzip;
        $error  = \$GunzipError;
    }
    else {
        #assume plain message
        return $message;
    }

    my $msg;
    &{$method}(\$message => \$msg)
      or die "uncompress failed: ${$error}";

    return $msg;
}

sub enchunk {
    my @p = validate_pos(
        @_,
        { type => SCALAR },
        { type => SCALAR, default => 'wan' },
    );

    my ($message, $size) = @p;

    $size = parse_size($size);

    if ( $size > 0
         && length $message > $size
    ) {
        my @chunks;
        while (length $message) {
            push @chunks, substr $message, 0, $size, '';
        }

        my $n_chunks = scalar @chunks;
        die 'Message too big' if $n_chunks > 128;

        my $magic          = pack('C*', 0x1e,0x0f); # Chunked GELF magic
        my $message_id     = pack('L*', irand(),irand());
        my $sequence_count = pack('C*', $n_chunks);

        my @chunks_w_header;
        my $sequence_number = 0;
        foreach my $chunk (@chunks) {
           push @chunks_w_header,
              $magic
              . $message_id
              . pack('C*',$sequence_number++)
              . $sequence_count
              . $chunk;
        }

        return @chunks_w_header;
    }
    else {
         return ($message);
    }
}

sub is_chunked {
    my @p = validate_pos(
        @_,
        { type => SCALAR },
    );
    
    my $chunk = shift @p;
    
    return $GELF_MSG_MAGIC eq substr $chunk, 0, 2;
}

sub decode_chunk {
    my @p = validate_pos(
        @_,
        { type => SCALAR },
    );
    
    my $encoded_chunk = shift;

    if ( is_chunked($encoded_chunk) ) {
        
        my $id      = join '', unpack('LL', substr $encoded_chunk,  2, 8);
        my $seq_no  = unpack('C',  substr $encoded_chunk, 10, 1);
        my $seq_cnt = unpack('C',  substr $encoded_chunk, 11, 1);
        my $data    = substr $encoded_chunk, 12;
        
        return {
            id              => $id,
            sequence_number => $seq_no,
            sequence_count  => $seq_cnt,
            data            => $data,
        };
    }
    else {
        die "message not chunked";
    }
}

sub parse_level {
    my @p = validate_pos(
        @_,
        { type => SCALAR }
    );
    
    my $level = shift @p;

    if ( $level =~ $LEVEL_NAME_REGEX ) {
        return $LEVEL_NAME_TO_NUMBER{$1};
    }
    elsif ( $level =~ /^(?:0|1|2|3|4|5|6|7)$/ ) {
        return $level;
    }
    else {
        die "level must be between 0 and 7 or a valid log level string";
    }
}

sub parse_size {
    my @p = validate_pos(
        @_,
        {
            callbacks => {
                compress_type => sub {
                    my $size = shift;
                    $size =~ /^(?:lan|wan|\d+)$/i
                        or die 'chunk size must be "lan", "wan", a positve integer, or 0 (no chunking)';
                },
            },
        },
    );

    my $size = lc(shift @p);

    # These default values below were determined by
    # examining the code for Graylog's implementation. See
    #  https://github.com/Graylog2/gelf-rb/blob/master/lib/gelf/notifier.rb#L62
    # I believe these are determined by likely MTU defaults
    #  and possible heasers like so...
    # WAN: 1500 - 8 b (UDP header) - 60 b (max IP header) - 12 b (chunking header) = 1420 b
    # LAN: 8192 - 8 b (UDP header) - 20 b (min IP header) - 12 b (chunking header) = 8152 b
    # Note that based on my calculation the Graylog LAN
    #  default may be 2 bytes too big (8154)
    # See http://stackoverflow.com/questions/14993000/the-most-reliable-and-efficient-udp-packet-size
    # For some discussion. I don't think this is an exact science!

    if ( $size eq 'wan' ) {
        $size = 1420;
    }
    elsif ( $size eq 'lan' ) {
        $size = 8152;
    }
    elsif ( $size eq '0' ) {
        $size = '0 but true';
    }

    return $size;
}

1;
__END__

=encoding utf-8

=head1 NAME

Log::GELF::Util - It's new $module

=head1 SYNOPSIS

    use Log::GELF::Util;

=head1 DESCRIPTION

Log::GELF::Util is ...

=head1 LICENSE

Copyright (C) Adam Clarke.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Adam Clarke E<lt>adam.clarke@strategicdata.com.auE<gt>

=cut

