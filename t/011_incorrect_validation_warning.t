#!/usr/bin/perl6

use v6;

use Test;

use Path::Router;

my $router = Path::Router.new;
{
    try {
        $router.add-route(
            '/foo/:bar' => (
                validations => {
                    baz => 'Int',
                },
            ),
        );
        
        my $warning;
        CATCH {
            when X::Path::Router::BadRoute {
                $warning = $_;
                $warning.resume;
            }
        }

        like(
            ~$warning,
            rx{"Validation provided for component :baz, but the path /foo/:bar doesn't contain a variable component with that name"},
            "got a warning"
        );
    }
}

done;
