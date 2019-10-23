FROM fedora

LABEL 'maintainer=Mitsuhiro Furuta <m-furuta@rc.jp.nec.com>'

ARG TZ
ARG http_proxy
ARG https_proxy

COPY hyperestraier build

RUN set -x \
	&& dnf install -y \
		gcc \
		make \
		which \
		zlib-devel \
		cronie \
		findutils \
		httpd \
		procps-ng \
		net-tools \
	\
	&& cd /build \
	&& tar xfz qdbm-1.8.75.tar.gz \
	&& cd qdbm-1.8.75 \
	&& ./configure --enable-zlib \
	&& make \
	&& make check \
	&& make install \
	&& make clean \
	\
	&& cd /build \
	&& tar xfz hyperestraier-1.4.13.tar.gz \
	&& cd hyperestraier-1.4.13 \
	&& ./configure \
	&& make \
	&& make check \
	&& make install \
	&& make clean \
	\
	&& dnf remove -y \
		gcc \
		make \
		which \
		zlib-devel \
	&& rm -rf /var/cache/dnf/* \
	&& dnf clean all

RUN set -x \
	&& cd /var/www/html \
	&& cp /build/dot.htaccess .htaccess \
	&& cp /usr/local/libexec/estseek.cgi . \
	&& cp /usr/local/share/hyperestraier/estseek.* . \
	&& mv estseek.conf estseek.conf.org

RUN set -x \
	&& mv /etc/httpd/conf/httpd.conf /etc/httpd/conf/httpd.conf.org \
	&& cat /etc/httpd/conf/httpd.conf.org \
		| sed '/^<Directory "\/var\/www\/html">/,/^</s/^\(\s*Options\).*/\1 All/' \
		| sed '/^<Directory "\/var\/www\/html">/,/^</s/^\(\s*AllowOverride\).*/\1 All/' \
		> /etc/httpd/conf/httpd.conf \
	&& diff -C 2 /etc/httpd/conf/httpd.conf.org /etc/httpd/conf/httpd.conf \
	|| echo '/etc/httpd/conf/httpd.conf changed.'
RUN systemctl enable httpd

EXPOSE 80

RUN systemctl enable crond

# Dockerfile 中の設定スクリプトを抽出するスクリプトを出力、実行
COPY Dockerfile .
RUN echo $'\
cat Dockerfile | sed -n \'/^##__BEGIN0/,/^##__END0/p\' | sed \'s/^#\s*//\' > startup.sh\n\
cat Dockerfile | sed -n \'/^##__BEGIN1/,/^##__END1/p\' | sed \'s/^#\s*//\' > crontab.index\n\
' > extract.sh && bash extract.sh

# docker-compose up の最後に実行される設定スクリプト
##__BEGIN0__startup.sh__
#
#	ln -v -fs ../usr/share/zoneinfo/$TZ /etc/localtime
#	crontab crontab.index
#	crontab -l
#
#	cd /var/lib/pv/hyperestraier
#	find documents -type f -name "*.html" | estcmd gather -cl -fh -cm casket - > /dev/null
##	find documents -type f -name "*.eml"  | estcmd gather -cl -fm -cm casket - > /dev/null
#	estcmd search -vh -max 3 casket 'Linux'
#
#	cd /var/www/html
#	ln -v -s /var/lib/pv/hyperestraier/documents .
#	cat estseek.conf.org \
#		| sed 's/^\(indexname:\).*/\1 \/var\/lib\/pv\/hyperestraier\/casket/' \
#		| sed 's/^\(replace:\).*^file.*/\1 ^file:\/\/\/var\/lib\/pv\/hyperestraier\/{{!}}\//' \
#		> estseek.conf
#	diff -C 2 estseek.conf.org estseek.conf \
#	|| echo '/var/www/html/estseek.conf changed.'
#
##__END0__startup.sh__

##__BEGIN1__crontab.index__
#
#	MAILTO=""
#
#	15 * * * * cd /var/lib/pv/hyperestraier; find documents -type f -name "*.html" | /usr/local/bin/estcmd gather -cl -fh -cm casket -
#	20 2 * * * cd /var/lib/pv/hyperestraier; /usr/local/bin/estcmd purge -cl casket
#
##__END1__crontab.index__

