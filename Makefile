.PHONY: run smoke

run:
	slangc main.sl --run

smoke:
	slangc smoke_auth/main.sl -o smoke_auth_bin && LIPO_MAIL_DEV=1 ./smoke_auth_bin
