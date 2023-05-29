ssh-keygen:
	ssh-keygen -t ed25519 -f ./terraform/short_lived/files/perf -N ''
	[ -z "${CI}" ] || echo ":add-mask:$(cat ./terraform/short_lived/files/perf)" && cat ./terraform/short_lived/files/perf

ssh-add:
	ssh-add ./terraform/short_lived/files/perf
