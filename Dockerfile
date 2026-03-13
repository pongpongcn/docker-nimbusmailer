FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends supervisor rsyslog postfix postfix-pcre dovecot-core opendkim \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i '/module(load="imklog"/ s|^|# |' /etc/rsyslog.conf

RUN postconf -e 'smtpd_sasl_type = dovecot' \
    && postconf -e 'smtpd_sasl_path = private/auth' \
    && postconf -e 'smtpd_sasl_security_options = noanonymous' \
    && postconf -e 'broken_sasl_auth_clients = yes' \
    && postconf -e 'smtpd_sasl_auth_enable = yes' \
    && postconf -e 'smtpd_relay_restrictions = permit_sasl_authenticated,permit_mynetworks,reject_unauth_destination' \
    && postconf -e 'smtp_tls_security_level = may' \
    && postconf -e 'smtpd_tls_security_level = may' \
    && postconf -e 'smtp_tls_note_starttls_offer = yes' \
    && postconf -e 'smtpd_tls_cert_file = /etc/postfix/tls/tls.crt' \
    && postconf -e 'smtpd_tls_key_file = /etc/postfix/tls/tls.key' \
    && postconf -e 'smtpd_tls_loglevel = 1' \
    && postconf -e 'smtpd_tls_received_header = yes' \
    && postconf -e 'smtpd_sender_restrictions = reject_authenticated_sender_login_mismatch' \
    && postconf -e 'smtpd_sender_login_maps = pcre:/etc/postfix/login_maps.pcre' \
    && postconf -e 'milter_default_action = accept' \
    && postconf -e 'milter_protocol = 6' \
    && postconf -e 'smtpd_milters = unix:opendkim/opendkim.sock' \
    && postconf -e 'non_smtpd_milters = unix:opendkim/opendkim.sock'

RUN mkdir -p /var/spool/postfix/opendkim \
    && chown opendkim:opendkim /var/spool/postfix/opendkim \
    && usermod -aG opendkim postfix

RUN postconf -M 'submission/inet=submission inet n - y - - smtpd' \
    && postconf -P 'submission/inet/syslog_name=postfix/submission' \
    && postconf -P 'submission/inet/smtpd_tls_security_level=encrypt' \
    && postconf -P 'submission/inet/smtpd_sasl_auth_enable=yes' \
    && postconf -P 'submission/inet/smtpd_tls_auth_only=yes' \
    && postconf -P 'submission/inet/smtpd_recipient_restrictions=permit_sasl_authenticated,reject'

RUN postconf -P 'smtp/inet/smtpd_sasl_auth_enable=no' \
    && postconf -P 'smtp/inet/smtpd_relay_restrictions=permit_mynetworks,reject_unauth_destination'

RUN cat > /etc/dovecot/conf.d/10-master.conf <<'EOF'
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}
EOF

RUN sed -i 's/^auth_mechanisms\s*=.*/auth_mechanisms = plain login/' /etc/dovecot/conf.d/10-auth.conf \
    && sed -i 's|^!include auth-system.conf.ext|#!include auth-system.conf.ext|' /etc/dovecot/conf.d/10-auth.conf \
    && sed -i 's|^#!include auth-passwdfile.conf.ext|!include auth-passwdfile.conf.ext|' /etc/dovecot/conf.d/10-auth.conf

RUN cat > /etc/dovecot/conf.d/auth-passwdfile.conf.ext <<'EOF'
passdb {
  driver = passwd-file
  args = scheme=CRYPT username_format=%u /etc/dovecot/users
}

userdb {
  driver = static
  args = uid=postfix gid=postfix home=/var/spool/postfix
}
EOF

COPY supervisord.conf /etc/supervisord.conf

EXPOSE 25 587

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord", "-n", "-c", "/etc/supervisord.conf"]