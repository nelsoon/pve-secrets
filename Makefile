VERSION := 0.1.0-1
PKG     := pve-secrets-manager
BUILD   := build
DEB     := $(BUILD)/$(PKG)_$(VERSION)_all.deb
R       := $(BUILD)/root

.PHONY: all lint deb clean

all: lint deb

lint:
	perl -It/lib -c bin/pve-secrets
	perl -c debian/integrate.pl
	node --check www/manager6/secrets/View.js
	sh -n debian/health && sh -n debian/prerm
	@cat debian/postinst.head debian/integrate.pl debian/postinst.tail | sh -n
	@cat debian/postrm.head debian/integrate.pl debian/postrm.tail | sh -n
	@echo "lint ok"

deb:
	rm -rf $(R)
	install -d $(R)/DEBIAN $(R)/usr/sbin $(R)/usr/lib/pve-secrets $(R)/lib/systemd/system \
	  $(R)/lib/systemd/system/openbao.service.d $(R)/etc/logrotate.d \
	  $(R)/usr/share/perl5/PVE/API2/Cluster $(R)/usr/share/pve-manager/js
	install -m644 PVE/API2/Cluster/Secrets.pm $(R)/usr/share/perl5/PVE/API2/Cluster/
	cat www/manager6/secrets/*.js > $(R)/usr/share/pve-manager/js/PVESecrets.js
	install -m755 bin/pve-secrets $(R)/usr/sbin/
	install -m755 debian/health $(R)/usr/lib/pve-secrets/health
	install -m644 debian/pve-secrets-converge.service debian/pve-secrets-converge.timer \
	  debian/pve-secrets-vip.service $(R)/lib/systemd/system/
	install -m644 debian/openbao-pve-secrets.conf $(R)/lib/systemd/system/openbao.service.d/pve-secrets.conf
	install -m644 debian/logrotate $(R)/etc/logrotate.d/pve-secrets
	cat debian/postinst.head debian/integrate.pl debian/postinst.tail > $(R)/DEBIAN/postinst
	cat debian/postrm.head debian/integrate.pl debian/postrm.tail > $(R)/DEBIAN/postrm
	chmod 755 $(R)/DEBIAN/postinst $(R)/DEBIAN/postrm
	install -m755 debian/prerm $(R)/DEBIAN/
	install -m644 debian/triggers $(R)/DEBIAN/
	echo /etc/logrotate.d/pve-secrets > $(R)/DEBIAN/conffiles
	printf 'Package: $(PKG)\nVersion: $(VERSION)\nArchitecture: all\nMaintainer: pve-secrets contributors\nDepends: openbao (>= 2.7), keepalived, pve-manager, pve-cluster, openssl, curl, perl\nRecommends: pve-identity-manager\nDescription: HA OpenBao secret store on Proxmox VE nodes\n Runs OpenBao on every node of a PVE cluster (Raft, static seal key in\n pmxcfs, VRRP address) and lets guests log in with pve-identity tokens.\n' > $(R)/DEBIAN/control
	dpkg-deb --root-owner-group --build $(R) $(DEB) >/dev/null
	@echo "built $(DEB)"

clean:
	rm -rf $(BUILD)
