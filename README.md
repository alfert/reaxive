# Reaxive

[![Build Status](https://travis-ci.org/alfert/reaxive.svg?branch=master)](https://travis-ci.org/alfert/reaxive)
[![Coverage Status](https://coveralls.io/repos/alfert/reaxive/badge.png?branch=master)](https://coveralls.io/r/alfert/reaxive?branch=master)
[![hex.pm version](https://img.shields.io/hexpm/v/reaxive.svg?style=flat)](https://hex.pm/packages/reaxive)
[![Inline docs](http://inch-ci.org/github/alfert/reaxive.svg?branch=master&style=flat-square)](http://inch-ci.org/github/alfert/reaxive)

Reaxive is a reactive event handling library, inspired by Elm (http://elm-lang.org) and Reactive Extensions.

## Current State

In the v0.0.3 series, we introduce cancellable generators. 

Subjects are a re-implementation of `Rx.Impl`. Major ideas:

* separate subscription handling from event handling
* subscriptions 
  * implement the boolean predicate `is_unsubscribed` as shown in the slides
  * functions for adding and removing subscribers from a subscription
* can subscriptions be implemented without a `GenServer`? 
* event handling should be done in a pure functional setting with explicit accumulators
  * Re-use `compose` and the `Rx.Sync` functions as combinators
  * combinators operate on a `Observeable`
  * Send composed events to subscribers
* we need a better mechanism to automatically stop processes or to detect that 
  they not running any more (==> monitoring or providing a general abstraction for 
  calling functions on not-existing gen-servers)


## History

The first code version (v0.0.1) has conceptual problems which showed up during testing.
As any observable lives in its own  process, we have maxium of concurrency.
This results in pushing events from the front while later transformations are
not properly setup. Due to this, some of the first events may be swallowed and
disappear, so the tests fail because not all events are piped through the
entire sequence of transformation.

The code v0.0.2 series is a major rework that implements ideas of 

* http://www.introtorx.com
* http://go.microsoft.com/fwlink/?LinkID=205219

and also inspired by Clojure's transducers introduced by Rich Hickey 

* http://blog.cognitect.com/blog/2014/8/6/transducers-are-coming
* http://clojure.org/transducers


## Contributing

Please use the GitHub issue tracker for 

* bug reports and for
* submitting pull requests

## License

Reaxive is provided under the Apache 2.0 License. 