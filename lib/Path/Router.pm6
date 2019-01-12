use v6;
unit class Path::Router:ver<0.3.0>:auth<github:zostay>;

use Path::Router::Route;
use X::Path::Router;

our $DEBUG = ?%*ENV<PATH_ROUTER_DEBUG>;

has Path::Router::Route @.routes;
has $.route-class = Path::Router::Route;

multi method add-route(Str $path, *%options --> Int) {
    @!routes.push: $!route-class.new(
        path => $path,
        |%options,
    );
    @!routes.elems;
}

multi method add-route(Str $path, %options --> Int) {
    self.add-route($path, |%options);
}

multi method add-route(*@pairs, *%pairs --> Int) {
    for (|@pairs, |%pairs)».kv -> (Str $path, %options) {
        self.add-route($path, |%options);
    }
    @!routes.elems;
}

multi method insert-route(Str $path, Int :$at = 0, *%options --> Int) {
    my $route = $!route-class.new(
        path => $path,
        |%options,
    );

    given $at {
        when 0                { @!routes.unshift: $route }
        when @!routes.end < * { @!routes.push: $route }
        default               { @!routes.splice($at, 0, $route) }
    }

    @!routes.elems;
}

multi method insert-route(Str $path, %options --> Int) {
    self.insert-route($path, |%options);
}

multi method insert-route(*@pairs, *%pairs --> Int) {
    for (|@pairs, |%pairs)».kv -> (Str $path, %options) {
        self.insert-route($path, |%options);
    }

    @!routes.elems;
}

multi method include-router(Str $path, Path::Router $router --> Int) {
    ($path eq '' || $path ~~ /\/$$/)
        || die X::Path::Router::BadInclusion.new;

    @!routes.push(
        |$router.routes.map: {
            my %attr = .copy-attrs;
            %attr<path> = $path ~ %attr<path>;
            .new(|%attr)
        }
    );

    @!routes.elems;
}

multi method include-router(Pair $pair --> Int) {
    my (Str $path, Path::Router $router) = $pair.kv;
    self.include-router($path, $router);
}

method match(Str $url is copy --> Path::Router::Route::Match) {
    $url  = IO::Spec::Unix.canonpath($url, :parent);
    $url .= subst(/^\//, '');

    my Str @parts = $url.comb(/ <-[ \/ ]>+ /);

    my Path::Router::Route::Match @matches;
    for @!routes -> $route {
        my $match = $route.match(@parts) or next;
        @matches.push: $match;
    }

    return Nil                        if @matches.elems == 0;
    return @matches[0]                if @matches.elems == 1;
    return self!disambiguate-matches($url, @matches);
}

method !disambiguate-matches(Str $path, Path::Router::Route::Match @matches --> Path::Router::Route::Match) {
    my Int $min;
    my Path::Router::Route::Match @found;

    for @matches -> $match {
        my $vars = $match.route.required-variable-component-names.elems;
        if !$min.defined || $vars < $min {
            @found = $match;
            $min = $vars;
        }
        elsif $vars == $min {
            @found.push: $match;
        }
    }

    die X::Path::Router::AmbiguousMatch::PathMatch.new(
        :matches(@found), :$path
    ) if @found.elems > 1;

    @found[0];
}

method !try-route(%url-map is copy, Path::Router::Route $route --> Str) {
    my @url;

    my $required = $route.required-variable-component-names;
    my $optional = $route.optional-variable-component-names;

    my %url-defaults;

    my %match = $route.defaults;

    for |$required.keys, |$optional.keys -> $component {
        next unless %match{$component} :exists;
        %url-defaults{$component} = %match{$component} :delete;
    }
    # any remaining keys in %defaults are 'extra' -- they don't
    # appear in the url, so they need to match exactly rather
    # than being filled in

    %url-map = |%url-defaults, |%url-map;

    my @keys = |%url-map.keys;

    my class X::RouteNotMatched is Exception {
        has Str $.reason;
        method new($reason) {
            self.bless(:$reason);
        }
        method message() { $!reason }
    }

    my sub debug { note [~] @_ if $DEBUG }

    debug("> Attempting to match ", $route.path, " to (", @keys.join(" / "), ")");

    (
        $required.elems <= @keys.elems <= $required.elems + $optional.elems + %match.elems
    ) || die X::RouteNotMatched.new("LENGTH DID NOT MATCH ({$required.elems} {$required.elems <= @keys.elems ?? "≤" !! "≰"} {@keys.elems} {@keys.elems <= $required.elems + $optional.elems + %match.elems ?? "≤" !! "≰"} {$required.elems} + {$optional.elems} + {%match.elems})"); #>>>>

    if my @missing = $required.keys.grep({ !(%url-map{$_} :exists) }) {
        debug("missing: {@missing}");
        die X::RouteNotMatched.new("MISSING ITEM [{@missing}]");
    }

    if my @extra = %url-map.keys.grep({
        $_ ∉ $required && $_ ∉ $optional && !%match{$_}
    }) {
        debug("extra: {@extra}");
        die X::RouteNotMatched.new("EXTRA ITEM[{@extra}]");
    }

    if my @nomatch = %match.keys.grep({
        %url-map{$_} :exists and %url-map{$_} ne %match{$_}
    }) {
        debug("no match: {@nomatch}");
        die X::RouteNotMatched.new("NO MATCH[{@nomatch}]");
    }

    for $route.components -> $component {
        if $route.is-component-variable($component) {
            debug("\t\t... found a variable ($component)");
            my $name = $route.get-component-name($component);

            unless $route.is-component-optional($component)
                && $route.defaults{$name}
                && $route.defaults{$name} eq %url-map{$name}
            {
                my $c = %url-map{$name};
                $c = join '/', @($c)
                    if $route.is-component-slurpy($component);
                @url.push: $c;
            }
        }

        else {
            debug("\t\t... found a constant ($component)");

            @url.push: $component;
        }

        debug("+++ URL so far ... ", @url.join("/"));
    }

    CATCH {
        when X::RouteNotMatched {
            debug('URL: ', @url.join("/"));
            debug("... ", $_);

            return Nil;
        }
    }

    @url.grep({ .defined }).join("/");
}

method uri-for(*%url-map --> Str) is DEPRECATED("'path-for'") {
    self.path-for(|%url-map);
}

method path-for(*%url-map is copy --> Str) {

    # anything => undef is useless; ignore it and let the defaults override it
    for %url-map {
        %url-map{$_} :delete unless %url-map{$_}.defined;
    }

    my @possible = gather for @!routes -> $route {
        my $url = self!try-route(%url-map, $route);
        take $[ $route, $url ] if $url.defined;
    }

    return Nil unless @possible;
    return @possible[0][1] if @possible == 1;

    my @found;
    my $min;
    for @possible -> $possible {
        my ($route, $url) = @($possible);

        temp %url-map = %url-map;

        my $required = $route.required-variable-component-names;
        my $optional = $route.optional-variable-component-names;

        my %url-defaults;

        my %match = $route.defaults;

        for $required.list, $optional.list -> $component {
            next unless %match{$component} :exists;
            %url-defaults{$component} = %match{$component} :delete;
        }
        # any remaining keys in %defaults are 'extra' -- they don't appear
        # in the url, so they need to match exactly rather than being filled
        # in

        %url-map = |%url-defaults, |%url-map;

        my $wanted = ($required.list ∪ $optional.list ∪ set %match.keys).SetHash;
        $wanted{$_} :delete for %url-map.keys;

        if (!$min.defined || $wanted.elems < $min) {
            @found = $possible;
            $min = $wanted.elems;
        }
        elsif ($wanted.elems == $min) {
            push @found, $possible;
        }
    }

    die X::Path::Router::AmbiguousMatch::ReverseMatch.new(
        match-keys => %url-map.keys,
        routes     => @found,
    ) if @found > 1;

    @found[0][1];
}

=begin pod

=NAME Path::Router - A tool for routing paths

=begin SYNOPSIS

  my $router = Path::Router.new;

  $router.add-route('blog' => (
      defaults => {
          controller => 'blog',
          action     => 'index',
      },
      # you can provide a fixed "target"
      # for a match as well, this can be
      # anything you want it to be ...
      target => My::App.get_controller('blog').get_action('index')
  ));

  $router.add-route('blog/:year/:month/:day' => (
      defaults => {
          controller => 'blog',
          action     => 'show_date',
      },
      # validate with ...
      validations => {
          # ... raw-Regexp refs
          year       => rx/\d ** 4/,
          # ... custom types you created
          month      => NumericMonth,
          # ... anon-subsets created inline
          day        => (anon subset NumericDay of Int where * <= 31),
      }
  ));

  $router.add-route('blog/:action/?:id' => (
      defaults => {
          controller => 'blog',
      },
      validations => {
          action  => rx/\D+/,
          id      => Int,  # also use Perl6 types too
      }
  ));

  # even include other routers
  $router.include-router( 'polls/' => $another_router );

  # ... in your dispatcher

  # returns a Path::Router::Route::Match object
  my $match = $router.match('/blog/edit/15');

  # ... in your code

  my $uri = $router.path-for(
      controller => 'blog',
      action     => 'show_date',
      year       => 2006,
      month      => 10,
      day        => 5,
  );

=end SYNOPSIS

=begin DESCRIPTION

This module provides a way of deconstructing paths into parameters
suitable for dispatching on. It also provides the inverse in that
it will take a list of parameters, and construct an appropriate
uri for it.

=head2 Reversable

This module places a high degree of importance on reversability.
The value produced by a path match can be passed back in and you
will get the same path you originally put in. The result of this
is that it removes ambiguity and therefore reduces the number of
possible mis-routings.

=head2 Verifiable

This module also provides additional tools you can use to test
and verify the integrity of your router. These include:

=item An interactive shell in which you can test various paths and see the
match it will return, and also test the reversability of that match.

=item A L<Test::Path::Router> module which can be used in your applications
test suite to easily verify the integrity of your paths.

=head2 Validated and Automatically Coerced

Each path may use one or more variables, each given a validation. If a numeric
type is used, the value passed on to the action will also be coerced into the
correct value.

=head2 Flexible

This module has no opinions about what it might be useful for. It simply produces a hash of values that can be used for dispatch, logging, or whatever your application is.

=end DESCRIPTION

=head1 ATTRIBUTES

=head2 has Path::Router::Route @.routes

Stores all the route objects that have been added to the router.

=head1 METHODS

=head2 method add-route

    method add-route(Str $path, *%options --> Int)

Adds a new route to the I<end> of the routes list.

Returns the number of routes stored.

=head2 method insert-route

    method insert-route(Str $path, *%options --> Int)

Adds a new route to the routes list. You may specify an C<at> parameter, which would
indicate the position where you want to insert your newly created route. The C<at>
parameter is the C<index> position in the list, so it starts at 0.

Returns the number of routes stored.

Examples:

    # You have more than three paths, insert a new route at
    # the 4th item
    $router.insert-route($path => %(
        at => 3, |%options
    ));

    # If you have less items than the index, then it's the same as
    # as add_route -- it's just appended to the end of the list
    $router.insert-route($path => %(
        at => 1_000_000, |%options
    ));

    # If you want to prepend, omit "at", or specify 0
    $router.insert_Route($path => %(
        at => 0, |%options
    ));

=head2 method include-router

    method include-router (Str $path, Path::Router $other-router --> Int)

This extracts all the route from C<$other-router> and includes them into
the invocant router and prepends C<$path> to all their paths.

It should be noted that this does B<not> do any kind of redispatch to the
C<$other-router>, it actually extracts all the paths from C<$other-router>
and inserts them into the invocant router. This means any changes to
C<$other-router> after inclusion will not be reflected in the invocant.

Returns the number of routes stored.

=head2 method match

    method match(Str $path --> Path::Router::Route::Match)

Return a L<Path::Router::Route::Match> object for the best route that matches the
given C<$path>, or C<undef> if no routes match.

The "best route" is chosen by matching the C<$path> against every route. If no
route matches, an undefined type object will be returned. If exactly one route
matches, a match for that route will be returned. If multiple routes match, the
one with the most required variables will be considered the best match and be
returned. If there's more than one with the same number of required variables,
an L<#X::Path::Router::AmbiguousMatch::PathMatch> exception is thrown. This
exception contains all the best matches, so your code can disambiguate them in
any way you want.

=head2 method path-for

    method path-for(*%path_descriptor --> Str)

Find the path that, when passed to C<< method match >>, would produce the
given arguments.  Returns the path without any leading C</>.  Returns an
undefined type-object if no routes match.

This will throw an L<#X::Path::Router::AmbiguousMatch::ReverseMatch> exception if
multiple URLs match. This exception includes the possible routes so your code
can disambiguate them in whatever fashion makes sense to you.

=head1 DEBUGGING

You can turn on the verbose debug logging with the C<PATH_ROUTER_DEBUG>
environment variable. Set that environment variable to a truthy value to enable
debugging.

=begin DIAGNOSTIC

=head2 X::Path::Router

All path router exceptions inherit from this exception class.

=head2 X::Path::Router::AmbiguousMatch::PathMatch

This exception is thrown when a path is found to match two different routes equally well.

Provides:

=item C<< method path(--> Str) >> returns the ambiguous path.

=item C<< method matches(--> Array) >> returns the best matches found.

=head2 X::Path::Router::AmbiguousMatch::ReverseMatch

This exception is thrown when two paths are found to match a given criteria when looking up the C<path-for> a path

Provides:

=item C<< method match-keys(--> Array[Str]) >> returns the mapping that was ambiguous

=item C<< method routes(--> Array[Str]) >> returns the best matches found

=head2 X::Path::Router::BadInclusion

This exception is thrown whenever an attempt is made to include one router in another incorrectly.

=head2 X::Path::Router::BadRoute

This exception is thrown when a route has some serious flaw.

Provides:

=item C<< method path(--> Str) >> returns the bad route

=head2 X::Path::Router::BadValidation

This is an L<#X::Path::Router::BadRoute> exception that is thrown when a validation for a variable that is not found in the path.

Provides:

=item C<< method validation(--> Str) >> returns the validation variable that was named in the route, but was not found in the path

=head2 X::Path::Router::BadSlurpy

This is an L<#X::Path::Router::BadRoute> exception that is thrown when a validation attempts to add a slurpy parameter that is not at the end of the path.

=end DIAGNOSTIC

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
