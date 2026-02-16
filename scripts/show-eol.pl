#!/bin/sh
# Shell/Perl bootstrap: shell runs this line, exec-ing Perl with -x to skip
# the shell preamble.  PERL_BADLANG=0 is set only when $MSYSTEM is defined
# (MSYS2/Git Bash) to suppress "Setting locale failed" warnings caused by
# LANG=en_US.UTF-8 not being recognized by Perl's C runtime on Windows.
# On Linux/macOS, locale warnings are preserved.
exec env ${MSYSTEM:+PERL_BADLANG=0} perl -x "$0" "$@"
#!perl
use strict;
use warnings;

=head1 NAME

show-eol.pl - Report line-ending style for one or more files

=head1 SYNOPSIS

  perl show-eol.pl <file> [file ...]
  perl show-eol.pl -v <file> [file ...]
  perl show-eol.pl --help

=head1 DESCRIPTION

Prints one row per file with:

  EolType  CRLF  LF  CR  Path

EolType is one of: CRLF, LF, CR, Mixed, None.

With -v / --verbose, each file is also printed line-by-line with a
3-character prefix indicating that line's ending:

  C    => CR
  L    => LF
  CL   => CRLF

=cut

sub usage {
  print <<'USAGE';
Usage:
  perl show-eol.pl [-h|--help] [-v|--verbose] <file> [file ...]

Options:
  -v, --verbose  Also print file lines with per-line EOL prefixes.
  -h, --help     Show this help text.

Summary columns:
  EolType  CRLF  LF  CR  Path
  EolType is one of: CRLF, LF, CR, Mixed, None.

Verbose prefixes:
  C    line ended with CR (\r)
  L    line ended with LF (\n)
  CL   line ended with CRLF (\r\n)
       line has no line terminator (last line only)

Examples:
  perl show-eol.pl README.md
  perl show-eol.pl a.txt b.txt
  perl show-eol.pl -v README.md
  perl -x show-eol.pl -h
USAGE
}

if (!@ARGV || grep { $_ eq '--help' || $_ eq '-h' } @ARGV) {
  usage();
  exit 0;
}

my $verbose = 0;
my @paths;
for my $arg (@ARGV) {
  if ($arg eq '-v' || $arg eq '--verbose') {
    $verbose = 1;
    next;
  }
  push @paths, $arg;
}
if (!@paths) {
  die "error: provide at least one file path\n";
}

my @rows;

for my $path (@paths) {
  if (!-e $path) {
    die "error: path does not exist: $path\n";
  }
  if (-d $path) {
    die "error: path is a directory: $path\n";
  }

  open my $fh, '<:raw', $path or die "error: failed to open '$path': $!\n";
  local $/;
  my $s = <$fh>;
  close $fh;
  $s = '' unless defined $s;

  my $crlf = () = ($s =~ /\r\n/g);
  (my $tmp = $s) =~ s/\r\n//g;
  my $cr = () = ($tmp =~ /\r/g);
  my $lf = () = ($tmp =~ /\n/g);

  my $type = 'Mixed';
  if ($crlf == 0 && $lf == 0 && $cr == 0) {
    $type = 'None';
  } elsif ($crlf > 0 && $lf == 0 && $cr == 0) {
    $type = 'CRLF';
  } elsif ($lf > 0 && $crlf == 0 && $cr == 0) {
    $type = 'LF';
  } elsif ($cr > 0 && $crlf == 0 && $lf == 0) {
    $type = 'CR';
  }

  push @rows, {
    path => $path,
    type => $type,
    crlf => $crlf,
    lf => $lf,
    cr => $cr,
  };
}

my $w_type = length('EolType');
my $w_crlf = length('CRLF');
my $w_lf = length('LF');
my $w_cr = length('CR');

for my $row (@rows) {
  $w_type = length($row->{type}) if length($row->{type}) > $w_type;
  $w_crlf = length("$row->{crlf}") if length("$row->{crlf}") > $w_crlf;
  $w_lf = length("$row->{lf}") if length("$row->{lf}") > $w_lf;
  $w_cr = length("$row->{cr}") if length("$row->{cr}") > $w_cr;
}

printf "%*s %*s %*s %*s  %s\n",
  $w_type, 'EolType',
  $w_crlf, 'CRLF',
  $w_lf, 'LF',
  $w_cr, 'CR',
  'Path';

for my $row (@rows) {
  printf "%*s %*d %*d %*d  %s\n",
    $w_type, $row->{type},
    $w_crlf, $row->{crlf},
    $w_lf, $row->{lf},
    $w_cr, $row->{cr},
    $row->{path};
}

if ($verbose) {
  for my $row (@rows) {
    print "\n==> $row->{path} <==\n";
    open my $fh, '<:raw', $row->{path}
      or die "error: failed to open '$row->{path}': $!\n";
    local $/;
    my $s = <$fh>;
    close $fh;
    $s = '' unless defined $s;

    while ($s =~ /(.*?)(\r\n|\n|\r|$)/gs) {
      my ($line, $ending) = ($1, $2);
      last if $ending eq '' && $line eq '' && pos($s) == length($s);
      my $prefix = '   ';
      if ($ending eq "\r\n") {
        $prefix = 'CL ';
      } elsif ($ending eq "\n") {
        $prefix = 'L  ';
      } elsif ($ending eq "\r") {
        $prefix = 'C  ';
      }
      print $prefix, $line, "\n";
      last if $ending eq '';
    }
  }
}

exit 0;
