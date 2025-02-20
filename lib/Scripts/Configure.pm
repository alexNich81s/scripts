=encoding utf8
=cut
package Scripts::Configure;
use 5.012;
use Exporter;
no warnings 'experimental';

our @ISA = qw/Exporter/;
our @EXPORT_OK = qw//;
our @EXPORT = qw/$defg/;
our $defg = 'main'; # default group
my $sortName = '_sort';
=comment new
my $config = Scripts::Configure->new ($file, $default);
    my $config = Scripts::Configure->new ("${configDir}weather", "${defConfDir}weather");
    use Scripts::scriptFunctions;
    my $config = conf 'weather'; # 简略写法.和上边作用一样.
=cut
sub new
{
    my $class = shift;
    my $config = $class->newEmpty;
    $config->parseConf(@_);
    $config;
}

sub newEmpty
{
    my $class = shift;
    my $config = { Conf => {}, Sort => {} };
    bless $config, $class;
}

sub readLine
{
    my $orig = shift;
    local ($_);
    $_ = $orig;
    chomp;
    s/^\s+//;s/\s+$//;
    s/^#.+$//;
    if (/^$/) {
        ($orig, 'comment');
    } elsif (/^\[(.+?)\]:(.+)/) { # config group
        ($orig, 'confg', $1, $2);
    } elsif (/^\[(.+?)\]/) { # simple group
        ($orig, 'simple', $1);
    } elsif (/^(.+?)\s*=\s*(.+)/) { # config
        ($orig, 'conf', $1, $2);
    }
}
=comment parseConf
my $ref = Scripts::Configure::parseConf (user-config, default-config);
=filestyle configure
[group1]
var = val
[defgroup]:name
var = val
=cut
#my $debug = 1;
sub parseConf
{
    #print @_;
    #local @ARGV = reverse (shift, shift);
    my ($self, $uf, $df) = @_;
    my ($user, $default, $userw, $defaultw);
    if ($^O eq 'MSWin32') {
        if (defined $uf) {
            open $userw, '<', "${uf}.windows" or undef $userw;
            open $user, '<', $uf or undef $user;
        }
        if (defined $df) {
            open $defaultw, '<', "${df}.windows" or undef $defaultw;
            open $default, '<', $df or undef $default;
        }
    } else {
        if (defined $uf) {
            open $user, '<', $uf or undef $user;
        }
        if (defined $df) {
            open $default, '<', $df or undef $default;
        }
    }
    my $found = 0;
    for my $fh ($default, $defaultw, $user, $userw) {
        $fh or next;
        $found = 1;
        my @this;
        while (<$fh>) {
            #say $l;
            #say $_;
            my (undef, $result, @match) = readLine $_;
            next if $result eq 'comment';
            if ($result eq 'confg') { # config group
                #say 'config group';
                @this = ($match[0], $match[1]);
            } elsif ($result eq 'simple') { # simple group
                #say 'simple group: '.$1;
                @this = $match[0];
            } elsif ($result eq 'conf') { # config
                #say "config:$1 = $2";
                $self->modify(@this, $match[0], $match[1]);
            }
        }
    }
    $self->{'Found'} = $found;
    $self;
}

sub found
{
    my $self = shift;
    $self->{'Found'};
}

sub hash
{
    my $self = shift;
    %{$self->hashref};
}

sub hashref
{
    my $self = shift;
    $self->{Conf};
}

sub origValue : lvalue
{
    my $self = shift;
    my $confhash = $self->hashref;
    my $sorthash = $self->sortRef;
    if (@_ == 1) {
        if (not exists $confhash->{$defg}) {
            $confhash->{$defg} = {};
            $sorthash->{$defg} = {};
        } elsif (ref $confhash->{$defg} ne 'HASH') {
            die;
        }
        $confhash->{$defg}{$_[0]};
    } elsif (@_ == 2) {
        if (not exists $confhash->{$_[0]}) {
            $confhash->{$_[0]} = {};
            $sorthash->{$_[0]} = {};
        } elsif (ref $confhash->{$_[0]} ne 'HASH') {
            die;
        }
        $confhash->{$_[0]}{$_[1]};
    } elsif (@_ == 3) {
        if (not exists $confhash->{$_[0]}) {
            $confhash->{$_[0]}{$_[1]} = {};
            $sorthash->{$_[0]}{$_[1]} = {};
        } elsif (ref $confhash->{$_[0]} ne 'HASH') {
            die;
        } elsif (not exists $confhash->{$_[0]}{$_[1]}) {
            $confhash->{$_[0]}{$_[1]} = {};
        } elsif (ref $confhash->{$_[0]}{$_[1]} ne 'HASH') {
            die;
        }
        $confhash->{$_[0]}{$_[1]}{$_[2]};
    } else {
        die;
    }
}

sub getOrigValue
{
    my $ret = eval { shift->origValue(@_) };
    $@ ? undef : $ret;
}

sub modify
{
    my $self = shift;
    my $value = pop;
    my $orig = eval { $self->origValue(@_) };
    return if ref $orig or $@; # cannot modify a group
    $self->origValue(@_) = $value;
    if (pop eq $sortName) {
        $self->parseSort(@_);
    }
    $self;
}

sub substConfigItem
{
    my ($self, $env, $conf) = @_;
    my ($var, $funGet);
    if ($env) {
        $var = $env;
        $funGet = sub { $ENV{+shift} };
    } else {
        $var = $conf;
        $funGet = sub { $self->get (split '::', shift) };
    }
    given ($var) {
        return '$' when '-';
        return $1 when /^(\s+)$/; # spaces returned as-is
        default {
            return $funGet->($_);
        }
    }
}

=comment get
$config->get ($var); # equal to $config->get ($defg, $var);
$config->get ($group, $var);
$config->get ($group, $subg, $var);
=cut
sub get
{
    my $self = shift;
    my $confhash = $self->hashref;
    my $ret = $self->getOrigValue (@_);
    if ($ret) {
        $ret =~ s/ \$ # a literal dollar
                   (?: # ${thing} for ENV vars
                        \{
                        ( [^\}]+ )
                        \}
                   | # or $[thing] for config items
                        \[
                        ( [^\]]+ )
                        \]
                   )
                /$self->substConfigItem($1, $2)/gex;
    }
    $ret;
}

sub getGroup
{
    my $confhash = shift->hashref;
    my $ret;
    if (@_ == 1) {
        $ret = $confhash->{$_[0]};
    } elsif (@_ == 2) {
        $ret = $confhash->{$_[0]}{$_[1]};
    } elsif (@_ == 0) {
        $ret = $confhash->{$defg};
    }
    ref $ret eq 'HASH' ? $ret : undef;
}

sub getGroups
{
    my $confhash = shift->hashref;
    if (@_ == 1) {
        my $ret = $confhash->{ + shift };
        if (ref $ret eq 'HASH') {
            return keys %$ret;
        }
    } elsif (@_ == 0) {
        return keys %$confhash;
    } elsif (@_ == 2) {
        return if ref $confhash->{$_[0]} ne 'HASH';
        my $ret = $confhash->{ + shift }{ + shift };
        if (ref $ret eq 'HASH') {
            return keys %$ret;
        }
    }
    return;
}

sub runHooks
{
    my ($self, $hookName) = @_;
    my $confhash = $self->hashref;
    ref $confhash->{Hooks} eq 'HASH' or return;
    ref $confhash->hashref->{Hooks}->{$hookName} eq 'HASH' or return;
    for (keys %{ $confhash->{Hooks}->{$hookName} }) {
        say "$hookName hook => $_";
        system $confhash->{Hooks}->{$hookName}->{$_};
    }
}

sub putEntries
{
    my ($self, $group, $ent) = @_;
    my $h = $self->hashref;
    my $ret;
    if (my @entries = @{$ent}) {
        $ret .= "[${group}]\n" if $group ne $defg; # 不是默认组才加 group 名
        for (@entries) {
            $ret .= $_.' = '.$h->{$group}{$_}."\n";
        }
        $ret .= "\n";
    }
    $ret;
}

sub outputFile
{
    my ($self) = @_;
    my $h = $self->hashref;
    my $order = sub { $a cmp $b };
    my $ret = '';
    # 先输出 $defg。
    my @entries = grep { not ref $h->{$defg}{$_} } $self->childList($defg);
    $ret .= $self->putEntries($defg, \@entries);

    # 顺序输出 Groups。
    for my $group ($self->childList) {
        my @all = $self->childList($group);
        my $flags = $self->getSortFlags($group);
        my $entriesFirst = 0;
        if ($flags->{groupOrder} eq 'G_LAST') { # 看一下有没有指定 G_LAST。如果有，先输出entries。
            $entriesFirst = 1;
        }
        $entriesFirst = !$entriesFirst if $flags->{'reverse'}; # reverse 最大。
        my @subgroups = grep { ref $h->{$group}{$_} eq 'HASH' } @all; # Hash 都是子组。
        my @entries = grep { not ref $h->{$group}{$_} } @all;
        $ret .= $self->putEntries($group, \@entries) if $group ne $defg and $entriesFirst;
        # 输出子组。
        for my $subg (@subgroups) {
            $ret .= "[${group}]:$subg\n";
            for my $entry ($self->childList($group, $subg)) {
                $ret .= $entry . ' = ' . $h->{$group}{$subg}{$entry}."\n";
            }
            $ret .= "\n";
        }
        $ret .= $self->putEntries($group, \@entries) if $group ne $defg and ! $entriesFirst;
    }
    $ret;
}

sub childList
{
    my $self = shift;
    my ($g, $sg);
    eval { ($g, $sg) = ([$self->getGroups(@_)], $self->sortGroup(@_)); };
    return () if $@;
    my $func = $self->getSortFunc(@_);
    my @path = @_;
    sort { $func->($self, $a, $b, @path) } @$g;
}

sub defaultOrder
{
    $a cmp $b;
}

sub sortRef
{
    shift->{Sort};
}

sub sortGroup : lvalue
{
    my $self = shift;
    my $group = $self->getGroups(@_) or die;
    my $sorthash = $self->sortRef;
    if (@_ == 0) {
        $sorthash->{$defg};
    } elsif (@_ == 1) {
        $sorthash->{$_[0]};
    } elsif (@_ == 2) {
        $sorthash->{$_[0]}{$_[1]};
    } else {
        die;
    }
}

sub sortFunc : lvalue
{
    my $self = shift;
    my $group = $self->sortGroup(@_);
    $group->{__func__};
}

sub sortWords : lvalue
{
    my $self = shift;
    my $group = $self->sortGroup(@_);
    $group->{__words__};
}

sub sortFlags : lvalue
{
    my $self = shift;
    my $group = $self->sortGroup(@_);
    $group->{__flags__};
}

sub getSortFunc
{
    my $self = shift;
    my $func;
    my @path = @_;
    for (0..@path) {
        eval { $func = $self->sortFunc(@path) };
        $func = undef if $@;
        if ($func) {
            last;
        }
        pop @path;
    }
    
    $func or $func = sub { $_[1] cmp $_[2] };
    $func;
}
# 默认 sort flags
my $defaultSortFlags = { defOrder => 'DEF_FIRST', groupOrder => 'G_NORMAL', 'reverse' => 0, };
sub getSortFlags
{
    my $self = shift;
    my $flags;
    my @path = @_;
    for (0..@path) {
        eval { $flags = $self->sortFlags(@path) };
        $flags = undef if $@;
        last if $flags;
        pop @path;
    }
    $flags or $flags = $defaultSortFlags;
    $flags;
}


sub byNumber { $_[0] <=> $_[1]; }
sub byChar { $_[0] cmp $_[1]; }
sub reversedSort { -shift; }
sub groupFirst
{
    my ($self, $first, $second, @path) = @_;
    ref $self->getGroup(@path, $second) cmp ref $self->getGroup(@path, $first); # '' cmp 'HASH'
}
sub groupLast
{
    my ($self, $first, $second, @path) = @_;
    ref $self->getGroup(@path, $first) cmp ref $self->getGroup(@path, $second); # '' cmp 'HASH'
}
# DEF_FIRST:DEF_LAST:NUM:CHAR:G_FIRST:G_LAST:G_NORMAL:REVERSE:a,b,c,d,e
# DEF_FIRST 代表在 words 中定义了的在前面。
# REVERSE 最大。如果定义了 REVERSE，那么 words 和所有其它的顺序都要翻转过来。
# 例如，如果同时定义 DEF_FIRST，那么在 words 中定义了的，会排在后面。
# sortFunc ($a, $b, @path);
sub parseSort
{
    my $self = shift;
    eval { $self->sortWords(@_) = {}; };
    return if $@;
    eval { $self->sortFlags(@_) = {}; };
    return if $@;
    eval { $self->sortFunc(@_) };
    return if $@;

    my $sortOrder = $self->get(@_, $sortName);
    my @flags = split /:/, $sortOrder, -1;
    my @words = split /,/, pop @flags;
    my $sortFunc;
    my ($comp, $groupOrder, $defOrder, $reverse)
        = (\&byChar,
           $defaultSortFlags->{'groupOrder'},
           $defaultSortFlags->{'defOrder'},
           $defaultSortFlags->{'reverse'});
    for (@flags) {
        $comp = \&byNumber when 'NUM';
        $comp = \&byChar when 'CHAR';
        $defOrder = $_ when /^DEF_(?:FIRST|LAST)$/;
        $groupOrder = $_ when /^G_(?:FIRST|LAST|NORMAL)$/;
        $reverse = 1 when 'REVERSE';
    }
    $self->sortFlags(@_) = { defOrder => $defOrder, groupOrder => $groupOrder, 'reverse' => $reverse };
    my $gFunc = sub { 0 };
    if ($groupOrder eq 'G_FIRST') {
        $gFunc = \&groupFirst;
    } elsif ($groupOrder eq 'G_LAST') {
        $gFunc = \&groupLast;
    }

    # 未出现在 words 里的，顺序值是 0。顺序值小的排在前面。
    # 如果定义在 words 里的在前，那么它们的顺序值应该是小于 0 的。
    my $this = $defOrder eq 'DEF_FIRST' ? -1 : 1;
    my $add = $defOrder eq 'DEF_FIRST' ? -1 : 1;
    my $w = $self->sortWords(@_);
    for ($defOrder eq 'DEF_FIRST' ? # 排在后面的，顺序值高。
         reverse @words : @words) {
        $w->{$_} = $this;
        $this += $add;
    }
    $self->sortFunc(@_) = sub {
        my ($self, $first, $second, @path) = @_;
        #ay ($first, $second);
        #my $s = $self->sortWords(@path);
        my $ret = $gFunc->($self, $first, $second, @path) ||
            $w->{$first} <=> $w->{$second} ||
            $comp->($first, $second);
        #ay $ret;
        $reverse ? -$ret : $ret; # REVERSE 最大
    };
}

1;
