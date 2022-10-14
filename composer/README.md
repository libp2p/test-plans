# Composer

Experiment to generate an interop dashboard and
deal with large interoperability matrixes.

This deserve a live demo and a discussion,
most of the code will be replaced by testground support.

A few notes to read during the demo.

This branch require testground's `feat/support-interop-matrix` which adds
a few templates.

## ./demo/composition-example.toml

shows an extension for compositions that contains:

```toml
[[groups]]
# the list of instances

[[runs]]
# the list of runs
# a run is of the form:
    id = 'run_id'

    [runs.test_params]
    # custom param for the whole run

    [[runs.groups]]
    id = 'id of a test instance'
    # TODO: maybe use 2 values: `id` and `group_id`,
    #       and default `id` to `group_id`
    instances = {count = 1}

    [[runs.groups.test_params]]
    # custom param for this instance

    [[run.groups]]
    id = 'another instances'
    # and so on.
```

## ./demo/composition-interop.toml

shows the template that would become the interop testing template.
It generates all the groups and all the runs.

## composer combine

This is the script that libp2p maintainers _should_ create and update.

`make ./demo/combinations.toml`

This loads resources files and generate a list of interop tests.

You can see all the generated combinations in `./demo/combinations.toml`.

This "only" generates pairs of versions, later we'll generate more complex pairs.

The output is the form:

```toml
[[runs]]
# the list of test runs with custom parameters

[[instances]]
# the list of test instances
```

## temporary testground support

`./demo/artifacts`

File generated during the build.
Might be useful for caching!

`./demo/composition-interop-runner.toml`

File used to emulate support for the `[[runs]]` field in compositions (it load a single run from the composition + its artifacts)

`composer foreach`

Script used to mimick testground support for compositions that contain multiple runs.

## Questions:

### What should the output look like?

I don't think testground can and should accomodate the use case:

> When I run my tests, the output should be an n-dimensional matrix.

I believe it should "just" output the `run-id;status`.

Much like the user implement their own test generation function (`composer combine`),
the user implement their own `run-id => point in N-D matrix` as a
(configurable) script.

### What should the CLI look like?

Proposition:

```sh
testground run composition --file=./composition-interop.toml --run-index=42 # build and run a single test
```

```sh
testground run composition --file=./composition-interop.toml # build & run all tests
```

```sh
testground run composition --file=./composition-interop.toml ... --result ./results.csv
# :warning: only support pass / fail
```

- How to deal with build & run failures:
  - If I try to run N tests for K different versions, and the build for 2 versions is failing:
  - Should Testground keep building, and run the tests for the builds that succeeded?
  - Proposal:
    - `testground run composition .... --continue-on-build-error`

### Are we happy with current templates?

Templating is a very useful scripting engine we integrate into testground.
For "simple" use case like parametrization (custom go version, generating large tests, etc) it
makes a lot of sense.

Are we happy with this approach? Another approach could be: the user generates toml files with their
own scripting engine (js, go, etc).

### Proposition: make template reusables with `partial`

```toml
(partial "./groups-go.toml" .) 
# loads a template from another file and execute it
# identical to a `{{ define "groups-go" }}` but can be reused accross files.
```

## Follow-ups

We have the list of artifacts at the end of the build,

```toml
rust-master = "892a93f7e73a"
"rust-v0.47.0" = "08198ea8a3ee"
"rust-v0.46.0" = "3e84da3a0e77"
"rust-v0.45.1" = "256c6805b1c2"
"rust-v0.44.0" = "5caac365e837"
go-master = "9dd68e54e1d1"
"go-v0.22" = "f41142781293"
"go-v0.21" = "31870c04b0db"
"go-v0.20" = "a1a9f7b142ab"
"go-v0.19" = "b0b301b81cef"
"go-v0.17" = "2bfde640aa3f"
"go-v0.11" = "c337c37e7977"
```

(related: [libp2p/test-plans/issues/31](https://github.com/libp2p/test-plans/issues/31))

- We could backup this list on every push to `libp2p/test-plans`
  - without master.
  - We tag and push to a registry, we pull before build.
  - With this: the test-plans never rebuild legacy code.
  - requires: secrets to a registry (dockerhub), but can live in the `libp2p/test-plans` repo.
- We could backup the build history for master
  - We cache this, "somewhere" (probably in the ci cache)
  - With this: the test-plans never rebuilds master from scratch.
  - requires: no secrets if we use the github ci cache.