use v6;

class PDF::Content::Text::Block {

    use PDF::Content::Text::Line;
    use PDF::Content::Text::Atom;
    use PDF::Content::Ops :OpNames, :TextMode;

    has Str     $.text;
    has Numeric $.font-size is required;
    has         $.font is required;
    has Numeric $.font-height = $!font.height( $!font-size );
    has Numeric $.font-base-height = $!font.height( $!font-size, :from-baseline );
    has Numeric $.line-height;
    has Numeric $!space-width;
    subset Percentage of Numeric where * > 0;
    has Percentage $.horiz-scaling = 100;
    has Numeric $.char-spacing = 0;
    has Numeric $.word-spacing = 0;
    has Numeric $!width;
    has Numeric $!height;
    has @.lines;
    has @.overflow is rw;
    has Str $!align where 'left'|'center'|'right'|'justify';
    has Str $.valign where 'top'|'center'|'bottom'|'text';
    has Numeric $.thickness is rw = 0.0; #| extra font thickness

    method actual-width  { @!lines.map( *.actual-width ).max }
    method actual-height { (+@!lines - 1) * $!line-height  +  $!font-height }

    multi submethod BUILD(Str     :$!text!,
                                  :$!font!,
			  Numeric :$!font-size = 16,
                          Bool    :$kern       = False,
			  |c) {

	$!space-width = $!font.stringwidth( ' ', $!font-size );

        my @chunks = flat $!text.comb(/ [ <![ - ]> [ \w | <:Punctuation> ] ]+ '-'? || . /).map( {
				    when /\n/  {' '}
                                    when $kern { $!font.kern($_, $!font-size).list }
                                    default    { $!font.filter($_) }
                                 });

        constant NO-BREAK-WS = "\c[NO-BREAK SPACE]" | "\c[NARROW NO-BREAK SPACE]" | "\c[WORD JOINER]";

        my PDF::Content::Text::Atom @atoms;

        while @chunks {
            my $content = @chunks.shift;
            my %atom = :$content;
            %atom<space> = @chunks && @chunks[0] ~~ Numeric
                ?? @chunks.shift
                !! 0;
            # don't atomize regular white-space
            next if $content ~~ /^\s/ && $content ne NO-BREAK-WS; 
            my Bool $followed-by-ws = ?(/^\s/ && $_ ne NO-BREAK-WS)
                with @chunks[0];
            %atom<width> = $!font.stringwidth($content, $!font-size, :$kern);
            my Bool $kerning = %atom<space> < 0;

	    do {
		when $kerning {
                    %atom<sticky> = True;
		}
		when $content eq NO-BREAK-WS {
                    %atom<elastic> = True;
                    %atom<sticky> = True;
                    @atoms[*-1].sticky = ? @atoms;
		}
		when $followed-by-ws {
                    %atom<elastic> = True;
                    %atom<space> = $!space-width;
		}
	    }

            my PDF::Content::Text::Atom $atom .= new( |%atom );

            my Str $encoded = [~] $!font.encode( $content );
            $atom.encoded = $encoded
                unless $encoded eq $content;

            @atoms.push: $atom;
        }

        self.BUILD( :@atoms, |c );
    }

    multi submethod BUILD(PDF::Content::Text::Atom :@atoms!,
                          Numeric :$!line-height = $!font-size * 1.1,
			  Numeric :$!horiz-scaling = 100,
			  Numeric :$!char-spacing = 0,
                          Numeric :$!word-spacing = 0,
                          Numeric :$!thickness = 0, #| extra fint thickness
                          Numeric :$!width?,        #| optional constraint
                          Numeric :$!height?,       #| optional constraint
                          Str :$!align = 'left',
                          Str :$!valign = 'text',
        ) is default {

        my PDF::Content::Text::Line $line;
        my Numeric $line-width = 0.0;
	my Numeric $char-count = 0.0;

	@atoms = @atoms;

        while @atoms {

            my @word;
            my $atom;
	    my $word-width = 0;

            repeat {
                $atom = @atoms.shift;
		$char-count += $atom.content.chars;
		$word-width += $atom.width + $atom.space;
                @word.push: $atom;
            } while $atom.sticky && @atoms;

            my Numeric $trailing-space = $atom.space;
	    if $trailing-space > 0 {
		$char-count += $trailing-space * $!font-size / $!space-width;
		$trailing-space += $!word-spacing;
		$word-width += $!word-spacing;
	    }

	    my Numeric $visual-width = $line-width + $word-width - $trailing-space;
	    $visual-width += ($char-count - 1) * $!char-spacing
		if $char-count && $!char-spacing > 0;
	    $visual-width *= $!horiz-scaling / 100
		if $!horiz-scaling != 100;

            if !$line || ($!width && $line.atoms && $visual-width > $!width) {
                last if $!height && (@!lines + 1)  *  $!line-height > $!height;
                $line = PDF::Content::Text::Line.new();
                $line-width = 0.0;
		$char-count = 0;
                @!lines.push: $line;
            }

            $line.atoms.append: @word;
            $line-width += $word-width;
        }

        my $width = $!width // self.actual-width
            if $!align eq 'justify';

        for @!lines {
            .atoms[*-1].elastic = False;
            .atoms[*-1].space = 0;
            .align($!align, :$width );
        }

        @!overflow = @atoms;
    }

    method width  { $!width //= self.actual-width }
    method height { $!height //= self.actual-height }
    method !dy {
        given $!valign {
            when 'center' { 0.5 }
            when 'bottom' { 1.0 }
            default       { 0 }
        };
    }
    method top-offset {
        self!dy * ($.height - $.actual-height);
    }

    method align($!align) {
        .align($!align)
            for self.lines;
    }

    method content(Bool :$nl,   # add trailing line 
                   Bool :$top,  # position from top
                   Bool :$left, # position from left;
                  ) {

        my @content = ( OpNames::SetTextLeading => [ $!line-height ], )
	    if $nl || +@!lines > 1;

        if $!thickness > 0 {
            # outline text to increase boldness
            @content.push( OpNames::SetTextRender => [ TextMode::FillOutlineText.value ] );
            @content.push( OpNames::SetLineWidth  => [ $!thickness / $!font-size ] );
        }

	my $space-size = -(1000 * $!space-width / $!font-size).round.Int;

        if $!valign ne 'text' {
            # adopt html style text positioning. from the top of the font, not the baseline.
            my $y-shift = $top ?? - $.top-offset !! self!dy * $.height;
            @content.push( OpNames::TextMove => [0, $y-shift - $!font-base-height ] );
        }

        my $dx = do given $!align {
            when 'center' { 0.5 }
            when 'right'  { 1.0 }
            default       { 0 }
        }
        my $x-shift = $left ?? $dx * $.width !! 0;

        for @!lines {
            @content.push: .content(:$.font-size, :$space-size, :$!word-spacing, :$x-shift);
            @content.push: OpNames::TextNextLine;
        }

        @content.pop
            if !$nl && @content;

        @content;
    }

}
