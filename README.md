# Reaxive

[![Build Status](https://travis-ci.org/alfert/reaxive.svg?branch=master)](https://travis-ci.org/alfert/reaxive)
[![Coverage Status](https://coveralls.io/repos/alfert/reaxive/badge.png?branch=master)](https://coveralls.io/r/alfert/reaxive?branch=master)
[![hex.pm version](https://img.shields.io/hexpm/v/reaxive.svg?style=flat)](https://hex.pm/packages/reaxive)
[![Inline docs](http://inch-ci.org/github/alfert/reaxive.svg?branch=master&style=flat-square)](http://inch-ci.org/github/alfert/reaxive)

Reaxive is a reactive event handling library, inspired by Elm (http://elm-lang.org) and Reactive Extensions. It implements the kind of asynchronous collections José Valim talked 
about in his keynotes on ElixirConf2014 and ElixirConfEU 2015. 

## Usage

### Preparations
To use Reaxive you have to add it to your Mix dependencies 

	deps: [
		{reaxive, "~> 0.0.3"}
	]

and add the `reaxive` and the `logger` application to your required applications

	applications: [:kernel, :reaxive, :logger]

### Using Reaxive

Now you can use Reaxive. All the combinators are defined in the module
`Reaxive.Rx` (see http://hexdocs.pm/reaxive/). Basically, they follow the
naming scheme from other reactive frameworks, such as Reactive Extensions
(.NET), RxScala or RxJS. Hence the wonderful marble diagrams of RX (see e.g.
http://rxmarbles.com/) can be used to understand the combinators' semantics.

	alias Reaxive.Rx
	1..100
	|> Rx.generate
	|> Rx.map(&(&+1))
	|> Rx.filter(&Integer.is_odd/1)
	|> Rx.as_text
	|> Rx.sum

The combinators are building a pipeline for event processing spawing new
processes on-demand. Adhering to the protocol should be sufficient that these
processes are automatically stopped again. This is extremely important, since otherwise
we get a process leak in our system which will eat up all system resources. 

The protocols, which lay the foundation for Reaxive, can also be found at
http://hexdocs.pm/reaxive/ .

## Future Development Steps

Important tasks for the future are: 

* simply and streamline the implementation
* implement José Valim's `async` operator to break a synchronous pipeline into 
  asynchronuous pieces 
* add more of the missing combinators 
* develop a concept of when and how to integrate with OTP Supervision
* gain experience of using in Reaxive, .e.g by applying to Phoenix Channels
* apply property based testing (using PropEr?) 
* apply the dialyzer 

## History
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