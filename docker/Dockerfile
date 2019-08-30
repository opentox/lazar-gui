FROM				archlinux/base
MAINTAINER  in-silico toxicology Gmbh

RUN         pacman-db-upgrade
RUN         pacman -Syyu --noconfirm 
RUN         pacman -S --noconfirm \
            base-devel \
            boost-libs \
            cmake \
            eigen3 \
            fontconfig \
            gcc-fortran \
            git \
            gsl \
            jre10-openjdk-headless \
            r \
            ruby \
            swig \
            python-pip \
            catdoc \
            wget
RUN         pacman -Scc --noconfirm

RUN         R -e "install.packages('Rserve', repos='http://rforge.net/')"
RUN         pip install xlsx2csv
RUN         useradd -ms /bin/bash ist

# mongodb has been removed from main repositories
USER        ist
WORKDIR     /home/ist
RUN         mkdir data
RUN         mkdir src
WORKDIR     /home/ist/src
RUN         wget https://aur.archlinux.org/cgit/aur.git/snapshot/mongodb-bin.tar.gz
RUN         tar -xvzf mongodb-bin.tar.gz
WORKDIR     /home/ist/src/mongodb-bin
RUN         makepkg -s --noconfirm

# installation requires root
USER        root
RUN         pacman -U --noconfirm /home/ist/src/mongodb-bin/mongodb-bin*.pkg.tar.xz 

# install lazar-gui gem
RUN         echo 'gem: --no-document' > /etc/gemrc

#RUN         gem install lazar-gui
RUN         gem install lazar
RUN         gem install qsar-report
RUN         gem install sinatra haml sass rdiscount unicorn

USER        ist
WORKDIR     /home/ist
RUN         rm -r src

# lazar-gui
RUN         git clone https://git.in-silico.ch/lazar-gui
WORKDIR     lazar-gui
RUN         git checkout prerelease

# SWAGGER for API
WORKDIR     /home/ist
RUN         git clone https://github.com/swagger-api/swagger-ui.git
COPY        swagger.html /home/ist/swagger-ui/dist/index.html

# TODO adjust to lazar-gui gem path
RUN         ln -s /home/ist/swagger-ui/dist/swagger-ui-bundle.js /home/ist/lazar-gui/public/swagger-ui-bundle.js
RUN         ln -s /home/ist/swagger-ui/dist/swagger-ui-standalone-preset.js /home/ist/lazar-gui/public/swagger-ui-standalone-preset.js
RUN         ln -s /home/ist/swagger-ui/dist/swagger-ui.css /home/ist/lazar-gui/public/swagger-ui.css

# start script
COPY        start.sh /home/ist/start.sh

ENTRYPOINT  ["/home/ist/start.sh"]
