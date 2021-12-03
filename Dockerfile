FROM osgeo/gdal:alpine-normal-v2.4.1

RUN mkdir -p /opt/src

WORKDIR /opt/src

# Pins that aren't part of the setup doc are:
# - sqlalchemy==1.1.9 to ensure we don't pull a py3 syntax SQLAlchemy
# - geopandas==0.6.1 to get to a low enough pyproj pin to work with our gdal universe deps
# - pyproj==1.9.3 because geopandas expresses >= 1.9.3 and there are lots of more recent versions
# - numpy==1.14.3 because it's a magic version based on some "how to install
# pandas in alpine" threads around the internet
# - webob because it's required but was missing
# Dependency installs are separated because some of them take _way longer_
# than others (pandas, numpy)

# System deps
RUN apk update \
    && apk add \
        build-base \
        gfortran \
        python2 \
        python2-dev \
        py-pip \
        R \
        gcc \
        libc-dev \
        linux-headers \
        postgresql-dev \
        libffi-dev \
        musl-dev \
    && ln -s /usr/include/locale.h /usr/include/xlocale.h

# super painful python deps
RUN pip install \
      shapely \
      pyproj==1.9.3 \
      numpy==1.14.3 \
      geopandas==0.6.3

# less painful python deps
RUN pip install \
      uwsgi \
      sqlalchemy==1.3.0 \
      Flask-User==0.6.19 \
      Flask-Migrate \
      Flask-Script \
      psycopg2-binary \
      PyGithub==1.35 \
      webob==1.8.7

COPY ./api/*.wsgi /opt/src/
COPY ./common/webapp /opt/src/webapp
COPY ./common/create_hit_daemon.py /opt/src/daemon/

ENTRYPOINT ["uwsgi"]