use v6;

use PDF::DAO::Type::PDF;

#| A minimal class for manipulating PDF graphical content
class PDF::Content::PDF
    is PDF::DAO::Type::PDF {

    use PDF::DAO::Tie;
    use PDF::DAO::Tie::Hash;

    use PDF::DAO::Stream;

    use PDF::Content::Graphics;
    use PDF::Content::Font;
    use PDF::Content::Page;
    use PDF::Content::PageNode;
    use PDF::Content::PageTree;
    use PDF::Content::Resourced;    
    use PDF::Content::ResourceDict;

    role Resources
	does PDF::DAO::Tie::Hash
	does PDF::Content::ResourceDict {
	    has PDF::DAO::Stream %.XObject is entry;
            has PDF::Content::Font %.Font is entry;
            has PDF::DAO::Dict $.ExtGState is entry;
    }

    my role XObject-Form
        does PDF::DAO::Tie::Hash
        does PDF::Content::Resourced
        does PDF::Content::Graphics {
            has Resources $.Resources is entry;
    }

    method xobject-form(|c) {
        PDF::Content::Page.xobject-form(:coerce(XObject-Form), |c);
    }

    role Page
	does PDF::DAO::Tie::Hash
	does PDF::Content::Page
	does PDF::Content::PageNode {

 	has Resources $.Resources is entry(:inherit);
	#| inheritable page properties
	has Numeric @.MediaBox is entry(:inherit,:len(4));
	has Numeric @.CropBox is entry(:inherit,:len(4));
	has Numeric @.BleedBox is entry(:len(4));
	has Numeric @.TrimBox is entry(:len(4));
	has Numeric @.ArtBox is entry(:len(4));

	my subset StreamOrArray of Any where PDF::DAO::Stream | Array;
	has StreamOrArray $.Contents is entry;

	method to-xobject(|c) {
	    PDF::Content::Page.to-xobject(self, :coerce(XObject-Form), |c);
	}
    }

    role Pages
	does PDF::DAO::Tie::Hash
	does PDF::Content::PageNode
	does PDF::Content::PageTree {

	has Resources $.Resources is entry(:inherit);
	#| inheritable page properties
	has Numeric @.MediaBox is entry(:inherit,:len(4));
	has Numeric @.CropBox is entry(:inherit,:len(4));

	has Page @.Kids is entry(:required, :indirect);
        has UInt $.Count is entry(:required);
    }

    role Catalog
	does PDF::DAO::Tie::Hash {
	has Pages $.Pages is entry(:required, :indirect);

	method cb-finish {
	    self.Pages.?cb-finish;
	}

    }

    has Catalog $.Root is entry(:required, :indirect);

    method cb-init {
	self<Root> //= { :Type( :name<Catalog> ), :Pages{ :Type( :name<Pages> ), :Kids[], :Count(0), } };
    }

    multi method page() {
	self.?Root.?Pages
    }

    multi method page(|c) is default {
	self.Root.Pages.page(|c)
    }

    for <add-page page-count> -> $meth {
        $?CLASS.^add_method($meth,  method (|a) { self.Root.Pages."$meth"(|a) });
    }

}
