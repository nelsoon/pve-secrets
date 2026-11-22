VERSION := 0.1.0-1
PKG     := pve-secrets-manager
BUILD   := build
DEB     := $(BUILD)/$(PKG)_$(VERSION)_all.deb
R       := $(BUILD)/root

.PHONY: all lint deb clean

all: lint deb

lint:
	perl -It/lib -c bin/pve-secrets
	@for f in debian/health debian/postinst debian/prerm debian/postrm; do sh -n $$f || exit 1; done
	@echo "lint ok"

deb:
	rm -rf $(R)
	install -d $(R)/DEBIAN $(R)/usr/sbin $(R)/usr/lib/pve-secrets $(R)/lib/systemd/system \
	  $(R)/lib/systemd/system/openbao.service.d $(R)/etc/logrotate.d
	install -m755 bin/pve-secrets $(R)/usr/sbin/
	install -m755 debian/health $(R)/usr/lib/pve-secrets/health
	install -m644 debian/pve-secrets-converge.service debian/pve-secrets-converge.timer \
	  debian/pve-secrets-vip.service $(R)/lib/systemd/system/
	install -m644 debian/openbao-pve-secrets.conf $(R)/lib/systemd/system/openbao.service.d/pve-secrets.conf
	install -m644 debian/logrotate $(R)/etc/logrotate.d/pve-secrets
	install -m755 debian/postinst debian/prerm debian/postrm $(R)/DEBIAN/
	echo /etc/logrotate.d/pve-secrets > $(R)/DEBIAN/conffiles
	printf 'Package: $(PKG)\nVersion: $(VERSION)\nArchitecture: all\nMaintainer: pve-secrets contributors\nDepends: openbao (>= 2.7), keepalived, pve-manager, pve-cluster, openssl, curl, perl\nRecommends: pve-identity-manager\nDescription: HA OpenBao secret store on Proxmox VE nodes\n Runs OpenBao on every node of a PVE cluster (Raft, static seal key in\n pmxcfs, VRRP address) and lets guests log in with pve-identity tokens.\n' > $(R)/DEBIAN/control
	dpkg-deb --root-owner-group --build $(R) $(DEB) >/dev/null
	@echo "built $(DEB)"

clean:
	rm -rf $(BUILD)
