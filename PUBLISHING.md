# Publishing Guide

This document covers how to build and publish this gem to RubyGems, and the
licensing/legal considerations that come with it.

## Background

This repository is a modernized fork of
[`FabioMR/firebird_adapter`](https://github.com/FabioMR/firebird_adapter) that
adds full Rails 8.1+ compatibility. It is licensed under the MIT License.
The upstream gem name `firebird_adapter` is already taken on RubyGems
(`firebird_adapter` 6.0.0 and older versions published by the original author).

## Obtaining push access

Trusted users can claim a gem ownership add request, provided they verify the
discovery that they own or control the project:

- `gem owner firebird_adapter -a YOUR_EMAIL` — requests ownership of the gem.
  If you do not get a response, ask the maintainers to add you as owner.
- For anything more involved, open a ruby-core ticket:
  `https://github.com/rubygems/rubygems/issues/new?assignees=&labels=gem-ownership&projects=&template=gem-ownership-request.yml`

> Reality check: the upstream gem on RubyGems is owned by the original author
> and is not under our control. Do not count on being granted ownership.

## Gem name collision

Because `firebird_adapter` already exists on RubyGems, **`gem push` will reject
`firebird_adapter 8.1.0`** unless the original owner grants ownership.

Options, in order of recommendation:

1. **Publish under a different name** (recommended).
   Pick a name that describes the Rails 8.1 fork, for example:
   `firebird_adapter_rails8`, `firebird_adapter_81`, `firebird_adapter_fork`.
   Update `spec.name` (and the README "Add to Gemfile" snippet) before building.
2. **Coordinate with the original author**.
   Ask `FabioMR` to either release upstream or add this fork's maintainers as
   gem owners, so we can publish under the canonical name.
3. **Use a private gem server** (Gemfury, a private gem server, or `gem` from a
   git source in the Gemfile). No public push required.

## Licensing requirements (MIT)

The MIT license grants broad rights but requires that the **copyright notice
and permission notice be preserved** in all copies or substantial portions. To
stay compliant:

- Keep the full `LICENSE.txt` in the repo and ship it in the gem.
  `spec.files = Dir["lib/**/*"]` in the gemspec intentionally excludes files
  outside `lib/`; if you want `LICENSE.txt` inside the built gem, add it to
  `spec.files` (gemspecs normally include `LICENSE.txt` explicitly).
- Keep the upstream copyright line for the original 2018 work and add the
  sections for the fork's contributors (already in place):
  ```
  Copyright (c) 2018 Fábio Rodrigues
  Copyright (c) 2024 Rolando Arnaudo
  Copyright (c) 2024 EmilioEduardoDb
  ```
- Set `spec.license = "MIT"` (already in place).

## Building and pushing

```sh
# 1. Build the gem (produces firebird_adapter-8.1.0.gem)
gem build firebird_adapter.gemspec

# 2. Verify the contents
gem contents firebird_adapter-8.1.0.gem
# (or unpack to inspect:)
gem unpack firebird_adapter-8.1.0.gem

# 3. Push to RubyGems (requires an account and API key, plus name ownership)
gem push firebird_adapter-8.1.0.gem
```

> `gem push` is irreversible per version. If a release-`abort`, `yank` is the
> escape hatch: `gem yank firebird_adapter -v 8.1.0` (only usable after push).

## Checklist before publishing

- [ ] `spec.name` set to the name you will actually push (unique on RubyGems)
- [ ] `spec.homepage` points at the fork URL (`https://github.com/rollyar/firebird_adapter`),
      not the upstream repo
- [ ] `spec.version` (currently `8.1.0`) matches the CHANGELOG release
- [ ] `LICENSE.txt` included in `spec.files` and lists every contributor
- [ ] Full test suite green against Firebird:
      `bundle exec rspec` (see README for DB/CI setup)
- [ ] CHANGELOG entry added for the release