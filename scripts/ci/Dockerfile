FROM ghcr.io/actions/actions-runner@sha256:5036480998280bb21e32ade9fe1b02b493861ac314b62ba1aea320b94f56ec97
USER root
RUN apt-get update && apt-get install -y --no-install-recommends libfontconfig1
RUN test -x /home/runner/externals/node24/bin/node && ln -s /home/runner/externals/node24/bin/node /usr/local/bin/node
USER runner
