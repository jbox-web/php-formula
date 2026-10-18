# -*- coding: utf-8 -*-
# vim: ft=sls
---
# Test-only: declare the sury-php repository the way VEILLECO's apt-formula does in
# production (deb822 file, key in its own keyring), so the formula installs the
# package with `use_external_repo: false`.
test-repo-sury-php-key:
  file.managed:
    - name: /etc/apt/keyrings/sury-php.gpg
    - source: https://packages.sury.org/php/apt.gpg
    - skip_verify: true
    - makedirs: true
    - mode: '0644'

test-repo-sury-php-source:
  file.managed:
    - name: /etc/apt/sources.list.d/sury-php.sources
    - mode: '0644'
    - contents: |
        Types: deb
        URIs: https://packages.sury.org/php
        Suites: {{ grains['oscodename'] }}
        Components: main
        Signed-By: /etc/apt/keyrings/sury-php.gpg
    - require:
      - file: test-repo-sury-php-key

test-repo-sury-php-refresh:
  cmd.run:
    - name: apt-get update
    - onchanges:
      - file: test-repo-sury-php-source
