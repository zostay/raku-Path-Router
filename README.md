NAME
====

Path::Router - A tool for routing paths

SYNOPSIS
========

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

    my $uri = $router.uri-for(
        controller => 'blog',
        action     => 'show_date',
        year       => 2006,
        month      => 10,
        day        => 5,
    );

DESCRIPTION
===========

This module provides a way of deconstructing paths into parameters suitable for dispatching on. It also provides the inverse in that it will take a list of parameters, and construct an appropriate uri for it.

Reversable
----------

This module places a high degree of importance on reversability. The value produced by a path match can be passed back in and you will get the same path you originally put in. The result of this is that it removes ambiguity and therefore reduces the number of possible mis-routings.

Verifyable
----------

This module also provides additional tools you can use to test and verify the integrity of your router. These include:

  * * An interactive shell in which you can test various paths and see the match it will return, and also test the reversability of that match.

  * * A [Test::Path::Router](Test::Path::Router) module which can be used in your applications test suite to easily verify the integrity of your paths.

Methods
=======

method add-route
----------------

    method add-route(Str $path, *%options)

Adds a new route to the *end* of the routes list.

method insert-route
-------------------

    method insert-route(Str $path, *%options)

Adds a new route to the routes list. You may specify an `at` parameter, which would indicate the position where you want to insert your newly created route. The `at` parameter is the `index` position in the list, so it starts at 0.

Examples:

    # You have more than three paths, insert a new route at
    # the 4th item
    $router->insert_route($path => (
        at => 3, %options
    ));

    # If you have less items than the index, then it's the same as
    # as add_route -- it's just appended to the end of the list
    $router->insert_route($path => (
        at => 1_000_000, %options
    ));

    # If you want to prepend, omit "at", or specify 0
    $router->insert_Route($path => (
        at => 0, %options
    ));

method include-router
---------------------

    method include-router (Str $path, Path::Router $other_router)

These extracts all the route from `$other_router` and includes them into the invocant router and prepends `$path` to all their paths.

It should be noted that this does **not** do any kind of redispatch to the `$other_router`, it actually extracts all the paths from `$other_router` and inserts them into the invocant router. This means any changes to `$other_router` after inclusion will not be reflected in the invocant.

has $.routes
------------

method match
------------

    method match(Str $path)

Return a [Path::Router::Route::Match](Path::Router::Route::Match) object for the first route that matches the given `$path`, or `undef` if no routes match.

method uri-for
--------------

    method uri-for(*%path_descriptor)

Find the path that, when passed to `$router->match `, would produce the given arguments. Returns the path without any leading `/`. Returns `undef` if no routes match.

Debugging
=========

You can turn on the verbose debug logging with the `PATH_ROUTER_DEBUG` environment variable.

DIAGNOSTIC
==========

X::Path::Router
---------------

All path router exceptions inherit from this exception class.

X::Path::Router::AmbiguousMatch::PathMatch
------------------------------------------

This exception is thrown when a path is found to match two different routes equally well.

X::Path::Router::AmbiguousMatch::ReverseMatch
---------------------------------------------

This exception is thrown when two paths are found to match a given criteria when looking up the `uri-for` a path

X::Path::Router::BadInclusion
-----------------------------

This exception is thrown whenever an attempt is made to include one router in another incorrectly.

X::Path::Router::BadRoute
-------------------------

This exception is thrown when a route has some serious flaw, such as a validation for a variable that is not found in the path.

BUG
===

All complex software has bugs lurking in it, and this module is no exception. If you find a bug please either email me, or add the bug to cpan-RT.

AUTHOR
======

Andrew Sterling Hanenkamp lthanenkamp@cpan.orggt

Based very closely on the original Perl 5 version by Stevan Little ltstevan.little@iinteractive.comgt

COPYRIGHT
=========

Copyright 2015 Andrew Sterling Hanenkamp.

LICENSE
=======

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

