use v6;

use CSS::Writer::BaseTypes;

class CSS::Writer
    is CSS::Writer::BaseTypes {

    use CSS::Grammar::AST;
    use CSS::Grammar::CSS3;

    has Str $.indent is rw;
    has Bool $.terse is rw;
    has Bool $.color-masks is rw;
    has %.color-values is rw;   #- maps color names to rgb values
    has %.color-names is rw;    #- maps rgb hex codes to named colors
    has $.ast is rw;

    submethod BUILD(:$!indent='',
                    :$!terse=False,
                    :$!color-masks=False,
                    :$color-names, :$color-values,
                    :$!ast,
        ) {

        sub build-color-names(%colors) {
            my %color-names;

            for %colors {
                my ($name, $rgb) = .kv;
                # output as ...gray not ...grey
                next if $name ~~ /grey/;
                my $hex = 256 * (256 * $rgb[0]  +  $rgb[1])  +  $rgb[2];
                %color-names{ $hex } = $name;
            }

            return %color-names;
        }

        if $!terse {
            $!color-masks //= True;
        }

        with $color-names {
            die ":color-names and :color-values are mutually exclusive options"
                if $color-values;

            given $color-names {
                when Bool { %!color-names = build-color-names( %CSS::Grammar::AST::CSS3-Colors )
                                if $_; }
                when Hash { %!color-names = build-color-names( $_ ) }
                default {
                    die 'usage :color-names [for CSS3 Colors] or :color-names(%table) [e.g. :color-names(CSS::Grammar::AST::CSS3-Colors)]';
                }
            }
        }
        else {
            with $color-values {
                when Bool { %!color-values = %CSS::Grammar::AST::CSS3-Colors
                                if $_; }
                when Hash { %!color-values = %$_ }
                default {
                    die 'usage :color-values [for CSS3 Colors] or :color-values(%table) [e.g. :color-values(CSS::Grammar::AST::CSS3-Colors)]';
                }
            }
        }

    }

    method Str {
        with $.ast {
            $.write( $_ );
        }
        else {
            nextsame;
        }
    }

    proto method write(|c --> Str) {*}

    #| @page   := $.write-at-keyw( 'page' )
    method write-at-keyw( Str $_ ) {
        '@' ~ $.write-ident( $_ );
    }

    #| 'foo', bar, 42 := $.write-args: [ :string<foo>, :ident<bar>, :num(42) ]
    method write-args( List $_ ) {
        $.write( $_, :sep(', ') );
    }

    #| [foo]   := $.write-attrib: [ :ident<foo> ]
    method write-attrib( List $_ ) {
        [~] flat '[', .map({ $.write( $_ ) }), ']';
    }

    #| /* These are */ /* comments * / */ := $.write-comment: [ "These are", "comments */" ]
    multi method write-comment( List $_ ) {
        .map({ $.write-comment( $_ ) }).join: $.nl;
    }
    multi method write-comment( Str $_ where /^ <CSS::Grammar::CSS3::comment> $/ ) {
        $_;
    }
    multi method write-comment( Str $_ ) {
        [~] '/* ', .trim.subst(/'*/'/, '* /'), ' */';
    }

    #| .my-class := $.write-class( 'my-class' )
    method write-class( Str $_) {
        '.' ~ $.write-name( $_ );
    }

    # for example, the body of an HTML style tag
    #| font-size:12pt; color:white; := $.write-declaration-list: [ { :ident<font-size>, :expr[ :pt(12) ] }, { :ident<color>, :expr[ :ident<white> ] } ]
    method write-declaration-list( List $_ ) {
        .map({
            my $prop = .<ident>:exists
                ?? :property(%$_)
                !! $_;

            $.write-indented( $prop, 2);
        }).join: $.nl;
    }

    #| { font-size:12pt; color:white; } := $.write-declarations: [ { :ident<font-size>, :expr[ :pt(12) ] }, { :ident<color>, :expr[ :ident<white> ] } ]
    method write-declarations( List $_ ) {
        (flat '{', $.write-declaration-list( $_ ), $.indent ~ '}').join: $.nl;
    }

    #| h1 := $.write-element-name('H1')
    method write-element-name( Str $_ ) {
        when '*' {'*'}  # wildcard namespace
        default  { $.write-ident( .lc ) }
    }

    #| 'foo', bar+42 := $.write-expr: [ :string<foo>, :op<,>, :ident<bar>, :op<+>, :num(42) ]
    method write-expr( List $_ ) {
        my $sep = '';

        [~] .map: -> $term is copy {

            $sep = '' if $term<op> && $term<op>;

            if %.color-values && $term<ident> && my $rgb = %.color-values{ $term<ident>.lc } {
                # substitute a named color with it's rgb value
                $term = {rgb => [ $rgb.map({ num => $_}) ]};
            }

            my $out = $sep ~ $.write($term);
            $sep = $term<op> && $term<op> ne ',' ?? '' !! ' ';
            $out;
        }
    }

    #| @charset 'utf-8';   := $.write( :at-rule{ :at-keyw<charset>, :string<utf-8> } )
    #| @import url('example.css') screen and (color); := $.write( :at-rule{ :at-keyw<import>, :url<example.css>, :media-list[ { :media-query[ { :ident<screen> }, { :keyw<and> }, { :property{ :ident<color> } } ] } ] } )
    #| @font-face { src:'foo.ttf'; } := $.write( :at-rule{ :at-keyw<font-face>, :declarations[ { :ident<src>, :expr[ :string<foo.ttf> ] }, ] } )
    #| @top-left { margin:5px; } :=   $.write( :at-rule{ :at-keyw<top-left>, :declarations[ { :ident<margin>, :expr[ :px(5) ] }, ] } )
    #| @media all { body { background:lime; }} := $.write( :at-rule{ :at-keyw<media>, :media-list[ { :media-query[ :ident<all> ] } ], :rule-list[ { :ruleset{ :selectors[ :selector[ { :simple-selector[ { :element-name<body> } ] } ] ], :declarations[ { :ident<background>, :expr[ :ident<lime> ] }, ] } } ]} )
    #| @namespace svg url('http://www.w3.org/2000/svg'); := $.write( :at-rule{ :at-keyw<namespace>, :ns-prefix<svg>, :url<http://www.w3.org/2000/svg> } )
    #| @page :first { margin:5mm; } := $.write( :at-rule{ :at-keyw<page>, :pseudo-class<first>, :declarations[ { :ident<margin>, :expr[ :mm(5) ] }, ] } )
    method write-at-rule( Hash $at-rule ) {
        my $at-keyw =  $.write( $at-rule, :nodes<at-keyw> );
        my $rhs = do given $at-keyw {
            when '@charset' { $.write($at-rule, :nodes<string>, :punc<;>) }
            when '@import' { $.write($at-rule, :nodes<url string media-list>, :punc<;>) }
            when '@media' { $.write($at-rule, :nodes<media-list rule-list>) }
            when '@namespace' { $.write($at-rule, :nodes<ns-prefix url>, :punc<;>) }
            when '@page' { $.write($at-rule, :nodes<pseudo-class declarations>) }
            default {
                $.write( $at-rule, :nodes<declarations> );
            }
        }
        [ $at-keyw, $rhs ].join: ' ';
    }

    #| lang(klingon) := $.write-func: { :ident<lang>, :args[ :ident<klingon> ] }
    method write-func( Hash $func) {
        sprintf '%s(%s)%s', $.write( $func, :node<ident> ), do {
            when $func<args>:exists {$.write( $func, :node<args> )}
            when $func<expr>:exists {$.write( $func, :node<expr> )}
            default {''};
        },
        $.write-any-comments( $func, ' ' );
    }

    #| #My-id := $.write-id( 'My-id' )
    method write-id(Str $_) {
        '#' ~ $.write-name($_);
    }

    #| -Moz-linear-gradient := $.write-ident('-Moz-linear-gradient' )
    method write-ident(Str $_ is copy) {
        my $pfx   = s/^"-"// ?? '-' !! '';
        my $minus = s/^"-"// ?? '\\-' !! '';
        [~] $pfx, $minus, $.write-name( $_ )
    }

    #| 42 := $.write-int(42)
    method write-int( Numeric $_ ) {
        $.write-num( $_ );
    }

    #| color := $.write-keyw('Color')
    method write-keyw( Str $_ ) {
        .lc;
    }

    #| projection, tv := $.write-media-list: [ :ident<projection>, :ident<tv> ]
    method write-media-list( List $_ ) {
        $.write( $_, :sep(', ') );
    }

    #| screen and (color) := $.write-media-query: [ { :ident<screen> }, { :keyw<and> }, { :property{ :ident<color> } } ]
    method write-media-query( List $_ ) {
        join(' ', .map({
            my $css = $.write( $_ );

            if .<property> {
                # e.g. color:blue => (color:blue)
                $css = [~] '(', $css.subst(/';'$/, ''), ')';
            }

            $css
        }) );
    }

    #| hi\! := $.write-name("hi\x021")
    method write-name( Str $_ ) {
        [~] .comb.map({
            when /<CSS::Grammar::CSS3::nmreg>/    { $_ };
            when /<CSS::Grammar::CSS3::regascii>/ { '\\' ~ $_ };
            default                               { .ord.fmt("\\%X ") }
        });
    }

    #| svg := $.write-ns-prefix( 'svg' )
    method write-ns-prefix( Str $_) {
        when ''  {''}   # no namespace
        when '*' {'*'}  # wildcard namespace
        default  { $.write-ident($_) }
    }

    #| 42 := $.write( :num(42) )

    #| ~= := $.write( :op<~=> )
    method write-op( Str $_ ) {
        .lc;
    }

    #| 100% := $.write-percent(100)
    method write-percent( Numeric $_ ) {
        $.write-num( $_ ) ~ '%';
    }

    #| !important := $.write-prio('important')
    method write-prio( Str $_ = 'important' ) {
        '!' ~ .lc;
    }

    #| color:red!important; := $.write-property: { :ident<color>, :expr[ :ident<red> ], :prio<important> }
    method write-property( Hash $property ) {
        my $sp = $!terse ?? '' !! ' ';
        my Str @p = $.write( $property, :node<ident> );
        @p.push: ':' ~ $sp ~ $.write($property, :node<expr>)
            if $property<expr>:exists;
        @p.push: $sp ~  $.write($property, :node<prio>)
            if $property<prio>:exists;
        @p.push: ';';
        my $comments = $.write-any-comments( $property, ' ' );
        @p.push: $comments if $comments;

        [~] @p;
    }

    #| :first := $.write-pseudo-class('first')
    method write-pseudo-class(Str $_) {
        ':' ~ $.write-name($_)
    }

    #| ::first-letter := $.write-pseudo-elem: 'first-letter'
    method write-pseudo-elem(Str $_) {
        '::' ~ $.write-name($_)
    }

    #| :lang(klingon) := $.write-pseudo-func: { :ident<lang>, :args[ :ident<klingon> ] }
    method write-pseudo-func( Hash $_ ) {
        ':' ~ $.write-func($_);
    }

    #| svg|circle := $.write-qname: { :ns-prefix<svg>, :element-name<circle> }
    method write-qname(Hash $qname) {
        my $out = $.write($qname, :node<element-name>);

        $out = $.write($qname, :node<ns-prefix>) ~ '|' ~ $out
            with $qname<ns-prefix>;

        $out ~= $.write-any-comments( $qname, ' ' );

        $out;
    }

    #| { h1 { margin:5pt; } h2 { margin:3pt; color:red; }} := $.write-rule-list: [ { :ruleset{ :selectors[ :selector[ { :simple-selector[ { :element-name<h1> } ] } ] ], :declarations[ { :ident<margin>, :expr[ :pt(5) ] }, ] } }, { :ruleset{ :selectors[ :selector[ { :simple-selector[ { :element-name<h2> } ] } ] ], :declarations[ { :ident<margin>, :expr[ :pt(3) ] }, { :ident<color>, :expr[ :ident<red> ] } ] } } ]
    method write-rule-list(List $_) {
        '{ ' ~ $.write( $_, :sep($.nl)) ~ '}';
    }

    #| a:hover { color:green; } := $.write-ruleset: { :selectors[ :selector[ { :simple-selector[ { :element-name<a> }, { :pseudo-class<hover> } ] } ] ], :declarations[ { :ident<color>, :expr[ :ident<green> ] }, ] }
    method write-ruleset(Hash $_) {
        [~] $.write($_, :nodes<selectors declarations>);
    }

    #| #container * := $.write-selector: [ { :id<container>}, { :element-name<*> } ]
    method write-selector(List $_) {
        $.write( $_ );
    }

    #| h1, [lang=en] := $.write-selectors: [ :selector[ { :simple-selector[ { :element-name<h1> } ] } ], :selector[ :simple-selector[ { :attrib[ :ident<lang>, :op<=>, :ident<en> ] } ] ] ]
    method write-selectors(List $_ ) {
        $.write( $_, :sep(', ') );
    }

    #| .foo:bar#baz := $.write-simple-selector: [ :class<foo>, :pseudo-class<bar>, :id<baz> ]
    method write-simple-selector(List $_) {
        $.write( $_, :sep("") );
    }

    #| 'I\'d like some \BEE f!' := $.write-string("I'd like some \x[bee]f!")

    #| h1 { color:blue; } := $.write-stylesheet: [ { :ruleset{ :selectors[ { :selector[ { :simple-selector[ { :qname{ :element-name<h1> } } ] } ] } ], :declarations[ { :ident<color>, :expr[ { :ident<blue> } ] }, ] } } ]
    method write-stylesheet(List $_) {
        my $sep = $.terse ?? "\n" !! "\n\n";
        $.write( $_, :$sep);
    }

    #| U+A?? := $.write-unicode-range: [0xA00, 0xAFF]
    method write-unicode-range(List $_ ) {
        my $range;
        my ($lo, $hi) = .map: {sprintf("%X", $_)};

        if !$lo eq $hi {
            # single value
            $range = sprintf '%x', $lo;
        }
        else {
            my $lo-sub = $lo.subst(/0+$/, '');
            my $hi-sub = $hi.subst(/F+$/, '');

            if $lo-sub eq $hi-sub {
                $range = $hi-sub  ~ ('?' x ($hi.chars - $hi-sub.chars));
            }
            else {
                $range = [~] $lo, '-', $hi;
            }
        }

        'U+' ~ $range;
    }

    #| url('snoopy.jpg') := $.write-url: 'snoopy.jpg'
    method write-url( Str $_ ) {
        sprintf "url(%s)", $.write-string( $_ );
    }

    #! generic handling of Lists, Pairs, Hashs and Lists
    multi method write(List $ast, Str :$sep=' ') {
        my Array %sifted = classify { .isa(Hash) && (.<comment>:exists) ?? 'comment' !! 'elem' }, $ast.list;
        my Str $out = (%sifted<elem> // []).list.map({ $.write( $_ ) }).join: $sep;
        $out ~= [~] %sifted<comment>.list.map({ ' ' ~ $.write($_) })
            if %sifted<comment>:exists && ! $.terse;
        $out;
    }

    multi method write(Pair $_) {
        my $node = .key.subst(/':'.*/, '');
        self."write-$node"( .value );
    }

    multi method write(Hash $ast!, :$node! ) {
        $.write( |($node => $ast{$node} ) );
    }

    multi method write(Hash $ast!, :$nodes!, Str :$punc='', Str :$sep=' ')  {
        my Str $str = $nodes.grep({ $ast{$_}:exists}).map({
                          $.write( |( .subst(/':'.*/, '') => $ast{$_}) )
                         }).join($sep)  ~  $punc;

        $str ~= $.write-any-comments( $ast, ' ' );

        $str;
    }

    multi method write(Hash $ast! ) {
        my %nodes =  $ast.keys.map: { .subst(/':'.*/, '') => $ast{$_} };
        $.write( |%nodes );
    }

    use CSS::Grammar::AST :CSSUnits;

    multi method write( *@args, *%opt ) is default {

        my $key = %opt.keys.sort.first({ $.can("write-$_") || (CSSUnits.enums{$_}:exists) })
            or die "unable to handle {%opt.keys} struct: {%opt.perl}";
        self."write-$key"(%opt{$key}, |%opt);
    }

    # -- helper methods --

    #| write comments, if applicable
    method write-any-comments( Hash $ast, $padding='' --> Str) {
        $ast<comment>:exists && ! $.terse
            ?? $padding ~ $.write($ast, :node<comment>)
            !! ''
    }

    #| handle indentation.
    method write-indented( Any $ast, Int $indent! --> Str) {
        my $sp = '';
        temp $.indent;
        $.indent ~= ' ' x $indent
            unless $.terse;
        $.indent ~ $.write( $ast );
    }

    method nl returns Str {
        $.terse ?? ' ' !! "\n";
    }

    #| 42deg   := $.write-num( 42,  'deg') or $.write( :deg(42) )
    #| 420hz   := $.write-num( 420, 'hz')  or $.write( :khz(.42) )
    #| 42mm    := $.write-num( 42,  'mm')  or $.write( :mm(42) ) or $.write-mm(42)
    #| 600dpi  := $.write-num( 600, 'dpi') or $.write( :dpi(600) )
    #| 20s     := $.write-num( 20,  's' )  or $.write( :s(20) )
    #| rgb(10, 20, 30) := $.write-color: [ :num(10), :num(20), :num(30) ], 'rgb' or $.write( :rgb[ :num(10), :num(20), :num(30) ] ) or $.write-rgb: [ :num(10), :num(20), :num(30) ]

    method FALLBACK ($meth-name, $val, |c) {
        if $meth-name ~~ /^ 'write-' (.+) $/ {
            my $units = ~$0;
            with CSSUnits.enums{$units} -> $type {
                my &meth = do given $type {
                    when 'color' { method ($v, |p) { $.write-color( $v, $units, |p) } }
                    default      { method (Numeric $v, |p) { $.write-num( $v, $units, |p) } }
                }
                # e.g. redispatch $.write-px( 12 ) as $.write-num( 12, 'px' )
                self.WHAT.^add_method($meth-name, &meth);
                return self."$meth-name"($val, |c);
            }
        }
        die "unknown method: $meth-name";
    }
}
