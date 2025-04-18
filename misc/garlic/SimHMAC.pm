package SimHMAC;
use strict;
require 5.000; 

# $Id: SimHMAC.pm,v 1.1 2009/10/18 08:19:44 sahadev Exp $

require Exporter;

@SimHMAC::ISA = qw( Exporter );
@SimHMAC::EXPORT = qw( &hmac &hmac_hex );

use integer;

#
# interface routine; returns a digest of a string passed as a parameter
#

sub Digest {
	my $context = &MD5Init();

	# this should be done always
	&MD5Update($context, $_[0], length($_[0]));

	return &MD5Final($context);
}

#
# same as Digest but returns digest in a printable (hex) form
#

sub HexDigest {
	return unpack("H*", &Digest(@_));
}


#
# MD5 implementation is below
#



# derived from the RSA Data Security, Inc. MD5 Message-Digest Algorithm

# Original context structure
# typedef struct {
#
#       UINT4 state[4];                                   /* state (ABCD) */
#       UINT4 count[2];        /* number of bits, modulo 2^64 (lsb first) */
#       unsigned char buffer[64];                         /* input buffer */
#
# } MD5_CTX;

# Constants for MD5Transform routine.

sub S11 {  7 }
sub S12 { 12 }
sub S13 { 17 }
sub S14 { 22 }
sub S21 {  5 }
sub S22 {  9 }
sub S23 { 14 }
sub S24 { 20 }
sub S31 {  4 }
sub S32 { 11 }
sub S33 { 16 }
sub S34 { 23 }
sub S41 {  6 }
sub S42 { 10 }
sub S43 { 15 }
sub S44 { 21 }

my $PADDING = join('', map(chr, (
     0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
);

# F, G, H and I are basic MD5 functions.

sub F { my ($x, $y, $z) = @_; ((($x) & ($y)) | ((~$x) & ($z))); }
sub G { my ($x, $y, $z) = @_; ((($x) & ($z)) | (($y) & (~$z))); }
sub H { my ($x, $y, $z) = @_; (($x) ^ ($y) ^ ($z)); }
sub I { my ($x, $y, $z) = @_; (($y) ^ (($x) | (~$z))); }


# ROTATE_LEFT rotates x left n bits.
# Note: "& ~(-1 << $n)" is not in C version
#
sub ROTATE_LEFT { my ($x, $n) = @_; ($x << $n) | (($x >> (32-$n) & ~(-1 << $n))); }

# FF, GG, HH, and II transformations for rounds 1, 2, 3, and 4.
# Rotation is separate from addition to prevent recomputation.

sub FF { 
	my ($a, $b, $c, $d, $x, $s, $ac) = @_;

	$a += &F($b, $c, $d) + $x + $ac;
	$a = &ROTATE_LEFT($a, $s);
	$a += $b;

	return $a;
}

sub GG { 
	my ($a, $b, $c, $d, $x, $s, $ac) = @_;

	$a += &G ($b, $c, $d) + $x + $ac;
	$a = &ROTATE_LEFT ($a, $s);
	$a += $b;

	return $a;
}

sub HH {
	my ($a, $b, $c, $d, $x, $s, $ac) = @_;
	$a += &H ($b, $c, $d) + $x + $ac;
	$a = &ROTATE_LEFT ($a, $s);
	$a += $b;

	return $a;
}

sub II {
	my ($a, $b, $c, $d, $x, $s, $ac) = @_;

	$a += &I ($b, $c, $d) + $x + $ac;
	$a = &ROTATE_LEFT ($a, $s);
	$a += $b;

	return $a;
}

# MD5 initialization. Begins an MD5 operation, writing a new context.

sub MD5Init  {
	my $context = {};

	@{$context-> {count}} = 2;
	$context-> {count}[0] = $context-> {count}[1] = 0;
	$context-> {buffer} = '';

	# Load magic initialization constants.

	@{$context-> {state}} = 4;
	$context-> {state}[0] = 0x67452301;
	$context-> {state}[1] = 0xefcdab89;
	$context-> {state}[2] = 0x98badcfe;
	$context-> {state}[3] = 0x10325476;

	return $context;
}

# MD5 block update operation. Continues an MD5 message-digest
# operation, processing another message block, and updating the context.

sub MD5Update {
	my ($context, $input, $inputLen) = @_;

	# Compute number of bytes mod 64
	my $index = (($context->{count}[0] >> 3) & 0x3F);

	# Update number of bits
	if (($context->{count}[0] += ($inputLen << 3)) < 
		($inputLen << 3))
	{
			$context->{count}[1]++;
			$context->{count}[1] += ($inputLen >> 29);
	}

	my $partLen = 64 - $index;

	# Transform as many times as possible.

	my $i;
	if ($inputLen >= $partLen) {

		substr($context -> {buffer}, $index, $partLen) = substr($input, 0, $partLen);

		&MD5Transform(\@{$context -> {state}}, $context -> {buffer});

		for ($i = $partLen; $i + 63 < $inputLen; $i += 64) {
			&MD5Transform ($context-> {state}, substr($input,$i));
		}

		$index = 0;
	} else {
		$i = 0;
	}

	# Buffer remaining input
	substr($context->{buffer}, $index, $inputLen-$i) = substr($input, $i, $inputLen-$i);
}

# MD5 finalization. Ends an MD5 message-digest operation, writing the
#	the message digest and zeroizing the context.

sub MD5Final {
	my $context = shift;

	# Save number of bits
	my $bits = &Encode (\@{$context->{count}}, 8);

	# Pad out to 56 mod 64.
	my ($index, $padLen);
	$index = ($context->{count}[0] >> 3) & 0x3f;
	$padLen = ($index < 56) ? (56 - $index) : (120 - $index);

	&MD5Update ($context, $PADDING, $padLen);

	# Append length (before padding)
	MD5Update ($context, $bits, 8);

	# Store state in digest
	my $digest = &Encode(\@{$context-> {state}}, 16);

	# &MD5_memset ($context, 0);

	return $digest;
}

# MD5 basic transformation. Transforms state based on block.

sub MD5Transform {
	my ($state, $block) = @_;

	my ($a,$b,$c,$d) = @{$state};
	my @x = 16;

	&Decode (\@x, $block, 64);

	# Round 1
	$a = &FF ($a, $b, $c, $d, $x[ 0], S11, 0xd76aa478); # 1 
	$d = &FF ($d, $a, $b, $c, $x[ 1], S12, 0xe8c7b756); # 2 
	$c = &FF ($c, $d, $a, $b, $x[ 2], S13, 0x242070db); # 3 
	$b = &FF ($b, $c, $d, $a, $x[ 3], S14, 0xc1bdceee); # 4 
	$a = &FF ($a, $b, $c, $d, $x[ 4], S11, 0xf57c0faf); # 5 
	$d = &FF ($d, $a, $b, $c, $x[ 5], S12, 0x4787c62a); # 6 
	$c = &FF ($c, $d, $a, $b, $x[ 6], S13, 0xa8304613); # 7 
	$b = &FF ($b, $c, $d, $a, $x[ 7], S14, 0xfd469501); # 8 
	$a = &FF ($a, $b, $c, $d, $x[ 8], S11, 0x698098d8); # 9 
	$d = &FF ($d, $a, $b, $c, $x[ 9], S12, 0x8b44f7af); # 10 
	$c = &FF ($c, $d, $a, $b, $x[10], S13, 0xffff5bb1); # 11 
	$b = &FF ($b, $c, $d, $a, $x[11], S14, 0x895cd7be); # 12 
	$a = &FF ($a, $b, $c, $d, $x[12], S11, 0x6b901122); # 13 
	$d = &FF ($d, $a, $b, $c, $x[13], S12, 0xfd987193); # 14 
	$c = &FF ($c, $d, $a, $b, $x[14], S13, 0xa679438e); # 15 
	$b = &FF ($b, $c, $d, $a, $x[15], S14, 0x49b40821); # 16 

	# Round 2
	$a = &GG ($a, $b, $c, $d, $x[ 1], S21, 0xf61e2562); # 17 
	$d = &GG ($d, $a, $b, $c, $x[ 6], S22, 0xc040b340); # 18 
	$c = &GG ($c, $d, $a, $b, $x[11], S23, 0x265e5a51); # 19 
	$b = &GG ($b, $c, $d, $a, $x[ 0], S24, 0xe9b6c7aa); # 20 
	$a = &GG ($a, $b, $c, $d, $x[ 5], S21, 0xd62f105d); # 21 
	$d = &GG ($d, $a, $b, $c, $x[10], S22,  0x2441453); # 22 
	$c = &GG ($c, $d, $a, $b, $x[15], S23, 0xd8a1e681); # 23 
	$b = &GG ($b, $c, $d, $a, $x[ 4], S24, 0xe7d3fbc8); # 24 
	$a = &GG ($a, $b, $c, $d, $x[ 9], S21, 0x21e1cde6); # 25 
	$d = &GG ($d, $a, $b, $c, $x[14], S22, 0xc33707d6); # 26 
	$c = &GG ($c, $d, $a, $b, $x[ 3], S23, 0xf4d50d87); # 27 
	$b = &GG ($b, $c, $d, $a, $x[ 8], S24, 0x455a14ed); # 28 
	$a = &GG ($a, $b, $c, $d, $x[13], S21, 0xa9e3e905); # 29 
	$d = &GG ($d, $a, $b, $c, $x[ 2], S22, 0xfcefa3f8); # 30 
	$c = &GG ($c, $d, $a, $b, $x[ 7], S23, 0x676f02d9); # 31 
	$b = &GG ($b, $c, $d, $a, $x[12], S24, 0x8d2a4c8a); # 32 

	# Round 3 
	$a = &HH ($a, $b, $c, $d, $x[ 5], S31, 0xfffa3942); # 33 
	$d = &HH ($d, $a, $b, $c, $x[ 8], S32, 0x8771f681); # 34 
	$c = &HH ($c, $d, $a, $b, $x[11], S33, 0x6d9d6122); # 35 
	$b = &HH ($b, $c, $d, $a, $x[14], S34, 0xfde5380c); # 36 
	$a = &HH ($a, $b, $c, $d, $x[ 1], S31, 0xa4beea44); # 37 
	$d = &HH ($d, $a, $b, $c, $x[ 4], S32, 0x4bdecfa9); # 38 
	$c = &HH ($c, $d, $a, $b, $x[ 7], S33, 0xf6bb4b60); # 39 
	$b = &HH ($b, $c, $d, $a, $x[10], S34, 0xbebfbc70); # 40 
	$a = &HH ($a, $b, $c, $d, $x[13], S31, 0x289b7ec6); # 41 
	$d = &HH ($d, $a, $b, $c, $x[ 0], S32, 0xeaa127fa); # 42 
	$c = &HH ($c, $d, $a, $b, $x[ 3], S33, 0xd4ef3085); # 43 
	$b = &HH ($b, $c, $d, $a, $x[ 6], S34,  0x4881d05); # 44 
	$a = &HH ($a, $b, $c, $d, $x[ 9], S31, 0xd9d4d039); # 45 
	$d = &HH ($d, $a, $b, $c, $x[12], S32, 0xe6db99e5); # 46 
	$c = &HH ($c, $d, $a, $b, $x[15], S33, 0x1fa27cf8); # 47 
	$b = &HH ($b, $c, $d, $a, $x[ 2], S34, 0xc4ac5665); # 48 

	# Round 4 
	$a = &II ($a, $b, $c, $d, $x[ 0], S41, 0xf4292244); # 49 
	$d = &II ($d, $a, $b, $c, $x[ 7], S42, 0x432aff97); # 50 
	$c = &II ($c, $d, $a, $b, $x[14], S43, 0xab9423a7); # 51 
	$b = &II ($b, $c, $d, $a, $x[ 5], S44, 0xfc93a039); # 52 
	$a = &II ($a, $b, $c, $d, $x[12], S41, 0x655b59c3); # 53 
	$d = &II ($d, $a, $b, $c, $x[ 3], S42, 0x8f0ccc92); # 54 
	$c = &II ($c, $d, $a, $b, $x[10], S43, 0xffeff47d); # 55 
	$b = &II ($b, $c, $d, $a, $x[ 1], S44, 0x85845dd1); # 56 
	$a = &II ($a, $b, $c, $d, $x[ 8], S41, 0x6fa87e4f); # 57 
	$d = &II ($d, $a, $b, $c, $x[15], S42, 0xfe2ce6e0); # 58 
	$c = &II ($c, $d, $a, $b, $x[ 6], S43, 0xa3014314); # 59 
	$b = &II ($b, $c, $d, $a, $x[13], S44, 0x4e0811a1); # 60 
	$a = &II ($a, $b, $c, $d, $x[ 4], S41, 0xf7537e82); # 61 
	$d = &II ($d, $a, $b, $c, $x[11], S42, 0xbd3af235); # 62 
	$c = &II ($c, $d, $a, $b, $x[ 2], S43, 0x2ad7d2bb); # 63 
	$b = &II ($b, $c, $d, $a, $x[ 9], S44, 0xeb86d391); # 64 

	$state -> [0] += $a;
	$state -> [1] += $b;
	$state -> [2] += $c;
	$state -> [3] += $d;

	# Zeroize sensitive information.
	# MD5_memset ((POINTER)x, 0, sizeof (x));
}

# Encodes input (UINT4) into output (unsigned char). Assumes len is
# a multiple of 4.

sub Encode {
	my ($input, $len) = @_;

	my $output = '';
	my ($i, $j);
	for ($i = 0, $j = 0; $j < $len; $i++, $j += 4) {
		substr($output, $j+0, 1) = chr($input -> [$i] & 0xff);
		substr($output, $j+1, 1) = chr(($input -> [$i] >> 8) & 0xff);
		substr($output, $j+2, 1) = chr(($input -> [$i] >> 16) & 0xff);
		substr($output, $j+3, 1) = chr(($input -> [$i] >> 24) & 0xff);
	}

	return $output;
}

# Decodes input (unsigned char) into output (UINT4). Assumes len is
# a multiple of 4.

sub Decode {
	my ($output, $input, $len) = @_;

	my ($i, $j);

	for ($i = 0, $j = 0; $j < $len; $i++, $j += 4) {
		$output -> [$i] = 
			(ord(substr($input, $j+0, 1))) | 
			(ord(substr($input, $j+1, 1)) << 8) |
			(ord(substr($input, $j+2, 1)) << 16) | 
			(ord(substr($input, $j+3, 1)) << 24);
	}
}

sub hmac
{
    my($data, $key) = @_;
    my $block_size = 64;
    
    $key = &Digest($key) if length($key) > $block_size;

    my $k_ipad = $key ^ (chr(0x36) x $block_size) . $data;

    my $k_opad = $key ^ (chr(0x5c) x $block_size) . &Digest($k_ipad);

    &Digest($k_opad);
}

sub hmac_hex { unpack("H*", &hmac); }


1;
