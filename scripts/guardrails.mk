# Guardrails: cheap greps that fail `make lint` on patterns the design rules forbid.
.PHONY: guard-bounce
# Interface springs never bounce (motion spec). Press bounce is Motion.press, a timing curve, so no spring needs it.
guard-bounce:
	@if grep -rnE 'bounce: *0?\.[1-9]' --include='*.swift' App Packages/CoreUI/Sources Packages/Features/Sources Packages/CoreKit/Sources; then \
		echo "guard-bounce: bounce springs on interface elements are not allowed; use Motion.out(...) (Motion.press for a glass press)"; exit 1; fi
