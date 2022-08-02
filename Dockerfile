# code: language=Dockerfile

# The code for the build image should be identical with the code in
# Dockerfile.django to use the caching mechanism of Docker.

# Ref: https://devguide.python.org/#branchstatus
FROM python:3.8.13-slim-bullseye@sha256:0e07cc072353e6b10de910d8acffa020a42467112ae6610aa90d6a3c56a74911 as base
FROM base as build
WORKDIR /app
RUN \
  apt-get -y update && \
  apt-get -y install --no-install-recommends \
    gcc \
    build-essential \
    dnsutils \
    default-mysql-client \
    libmariadb-dev-compat \
    postgresql-client \
    xmlsec1 \
    git \
    uuid-runtime \
    && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists && \
  true
COPY requirements.txt ./
# CPUCOUNT=1 is needed, otherwise the wheel for uwsgi won't always be build succesfully
# https://github.com/unbit/uwsgi/issues/1318#issuecomment-542238096
RUN CPUCOUNT=1 pip3 wheel --wheel-dir=/tmp/wheels -r ./requirements.txt


FROM build AS collectstatic

USER root
ENV \
  # This will point yarn to whatever version of node you decide to use
  # due to the use of nodejs instead of node name in some distros
  node="nodejs"
RUN \
  apt-get -y update && \
  apt-get -y install --no-install-recommends apt-transport-https ca-certificates curl wget gnupg && \
  curl -sSL https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add --no-tty - && \
  echo 'deb https://deb.nodesource.com/node_14.x bullseye main' > /etc/apt/sources.list.d/nodesource.list && \
  echo 'deb-src https://deb.nodesource.com/node_14.x bullseye main' >> /etc/apt/sources.list.d/nodesource.list && \
  apt-get update -y -o Dir::Etc::sourcelist="sources.list.d/nodesource.list" \
  -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" && \
  curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - && \
  wget https://github.com/yarnpkg/yarn/releases/download/v1.22.10/yarn_1.22.10_all.deb && \
  dpkg -i yarn_1.22.10_all.deb && \
  echo "$(yarn --version)" && \
  apt-get -y install --no-install-recommends nodejs && \
  echo "$(node --version)" && \
  apt-get clean && \
  rm yarn_1.22.10_all.deb && \
  rm -rf /var/lib/apt/lists && \
  true

RUN pip3 install \
	--no-cache-dir \
	--no-index \
  --find-links=/tmp/wheels \
	-r ./requirements.txt

COPY components/ ./components/
RUN \
  cd components && \
  yarn

COPY manage.py ./
COPY dojo/ ./dojo/

RUN env DD_SECRET_KEY='.' python3 manage.py collectstatic --noinput && true

FROM nginx:1.23.1-alpine@sha256:87fb6f4040ffd52dd616f360b8520ed4482930ea75417182ad3f76c4aaadf24f
ARG uid=1001
ARG appuser=defectdojo
COPY --from=collectstatic /app/static/ /usr/share/nginx/html/static/
COPY wsgi_params nginx/nginx.conf nginx/nginx_TLS.conf /etc/nginx/
COPY docker/entrypoint-nginx.sh /
RUN \
  apk add --no-cache openssl && \
  chmod -R g=u /var/cache/nginx && \
  mkdir /var/run/defectdojo && \
  chmod -R g=u /var/run/defectdojo && \
  mkdir -p /etc/nginx/ssl && \
  chmod -R g=u /etc/nginx && \
  true
ENV \
  DD_UWSGI_PASS="uwsgi_server" \
  DD_UWSGI_HOST="uwsgi" \
  DD_UWSGI_PORT="3031" \
  GENERATE_TLS_CERTIFICATE="false" \
  USE_TLS="false" \
  NGINX_METRICS_ENABLED="false" \
  METRICS_HTTP_AUTH_USER="" \
  METRICS_HTTP_AUTH_PASSWORD=""
USER ${uid}
EXPOSE 8080
ENTRYPOINT ["/entrypoint-nginx.sh"]
