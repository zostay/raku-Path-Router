use v6;

use X::Path::Router;

class Path::Router::Route { ... }

class Path::Router::Route::Match {
    has Str $.path;
    has %.mapping;
    has Path::Router::Route $.route handles <target>;
}

class Path::Router::Route {

    has Str $.path;
    has %.defaults; # is copy
    has %.validations; # is copy
    has Str @.components = self!build-components(); # is no-clone
    has Int $.length = self!build-length; # is no-clone
    has Int $.length-without-optionals = self!build-length-without-optionals; # is no-clone
    has $.required-variable-component-names = self!build-required-variable-component-names; # is no-clone
    has $.optional-variable-component-names = self!build-optional-variable-component-names; # is no-clone
    has $.target;

    method copy-attrs(--> Hash) {
        return (
            path        => $!path,
            defaults    => %!defaults.clone,
            validations => %!validations.clone,
            target      => $!target,
        ).hash;
    }

    method has-defaults(--> Bool) {
        ?%!defaults;
    }

    method has-validations(--> Bool) {
        ?%!validations;
    }

    submethod TWEAK {
        self!validate-configuration;
    }

    submethod !validate-configuration {
        # If there's a slurpy, it had better be the last one
        die X::Path::Router::BadSlurpy.new(:$!path)
            if @!components > 1
            && self.is-component-slurpy(@!components[0..*-2].any);

        return unless self.has-validations;

        # Get the names of all the variable components
        my $components = set @!components.grep({
            self.is-component-variable($^comp)
        }).map({
            self.get-component-name($^comp)
        });

        # Make we only have validations for variables in the path
        for %!validations.keys -> $validation {
            if $validation ∉ $components {
                die X::Path::Router::BadValidation.new(:$validation, :$!path);
            }
        }
    }

    method !build-components {
        $!path.comb(/ <-[ \/ ]>+ /).grep({ .chars });
    }

    method !build-length {
        @!components.elems;
    }

    method !build-length-without-optionals {
        @!components.grep({ !self.is-component-optional($^component) }).elems;
    }

    method !build-required-variable-component-names {
        return set @!components.grep({
             self.is-component-variable($^comp) &&
            !self.is-component-optional($comp)
        }).map({
            self.get-component-name($^comp)
        });
    }

    method !build-optional-variable-component-names {
        return set @!components.grep({
            self.is-component-variable($^comp) &&
            self.is-component-optional($comp)
        }).map({
            self.get-component-name($^comp)
        });
    }

    # misc

    method create-default-mapping(--> Hash) {
        %(%!defaults.map({ .key => .value.clone }));
    }

    method has-validation-for(Str $name --> Bool) {
        %!validations{$name} :exists
    }

    # component checking

    method is-component-slurpy(Str $component --> Bool) {
        ?($component ~~ / ^ <[*+]> \: /);
    }

    method is-component-optional(Str $component --> Bool) {
        ?($component ~~ / ^ <[*?]> \: /);
    }

    method is-component-variable(Str $component --> Bool) {
        ?($component ~~ / ^ <[?*+]> ? \: /);
    }

    method get-component-name(Str $component --> Str) {
        $component ~~ / ^ <[?*+]> ? \: $<name> = [ .* ] $$ /;
        ~$<name>;
    }

    method has-slurpy-match(--> Bool) {
        return False unless @!components;
        self.is-component-slurpy(@!components[*-1])
    }

    method match(@parts --> Path::Router::Route::Match) {
        # No match if the parts length is not long enough
        return Nil unless @parts >= $!length-without-optionals;

        # No match if parts is too long (unless we're slurpy, then it's fine)
        return Nil unless self.has-slurpy-match || $!length >= @parts;

        # Build the default mapping, shallow cloning any refs
        my %mapping = $.has-defaults ?? self.create-default-mapping !! ();

        # a working copy of parts we'll shift from as we go
        my @wc-parts = @parts;

        for @!components -> $c {
            unless @wc-parts {
                die "should never get here: " ~
                    "no @parts left, but more required components remain"
                        if ! self.is-component-optional($c);
                last;
            }

            my $part;

            # Slurpy sucks up the rest of the parts
            if self.is-component-slurpy($c) {
                $part = @wc-parts.clone.List;
                @wc-parts = ();
            }

            # Or just get the next part
            else {
                $part = @wc-parts.shift;
            }

            # If this is a variable, process it
            if self.is-component-variable($c) {

                # The variable name
                my $name = self.get-component-name($c);

                # Validate the value for the variable if needed
                if self.has-validation-for($name) {
                    my $v = %!validations{$name};

                    # Automatically coerce the value first, if needed
                    my $test-part = $part;
                    try {
                        given $v {
                            when UInt { $test-part .= UInt }
                            when Int  { $test-part .= Int }
                            when Num  { $test-part .= Num }
                            when Rat  { $test-part .= Rat }
                        }
                    }

                    # Apply the validation check
                    my $match = $test-part ~~ $v;

                    # Regexes must be a total match
                    if ($match ~~ Match) {
                        return Nil
                            unless $match && $match eq $test-part;
                    }

                    # Anything else matches whatever it matches
                    else {
                        return Nil unless $match;
                    }

                    # store the coerced version
                    $part = $test-part;
                }

                # Variable is valid and ready to map
                %mapping{$name} = $part;
            }

            # Otherwise, path must eq component
            else {
                return Nil unless $c eq $part;
            }
        }

        # Successful match, construct and return
        return Path::Router::Route::Match.new(
            path    => @parts.join('/'),
            route   => self,
            mapping => %mapping,
        );
    }

}

=begin pod

=TITLE Path::Router::Route;

=SUBTITLE An object to represent a route

=begin DESCRIPTION

This object is created by L<Path::Router> when you call the
C<add-route> method. In general you won't ever create these objects
directly, they will be created for you and you may sometimes
introspect them.

=end DESCRIPTION

=head1 Attributes

=head2 has $.path

=head2 has $.target

=head2 has $.components>

=head2 has $.length

=head2 has %.defaults

=head2 has %.validations

=head1 Methods

=head2 method has-defaults

=head2 method has-validations

=head2 method has-validation-for

=head2 method create-default-mapping

=head2 method match

=head1 Component checks

=head2 method get-component-name

    method get-component-name(Str $component)

=item method is-component-optional

    method is-component-optionaal(Str $component)

=item method is-component-variable

    method is-component-variable(Str $component)

=head1 Length methods

=item method length-without-optionals

=begin AUTHOR

Andrew Sterling Hanenkamp E<lt>hanenkamp@cpan.orgE<gt>

Based very closely on the original Perl 5 version by
Stevan Little E<lt>stevan.little@iinteractive.comE<gt>

=end AUTHOR

=for COPYRIGHT
Copyright 2015 Andrew Sterling Hanenkamp.

=for LICENSE
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=end pod
