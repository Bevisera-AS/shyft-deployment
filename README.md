# Shyft Helm charts

This address is a Helm repository. It publishes charts that run the [Shyft](https://gitlab.com/shyft-os/shyft)
hydrology micro-services on Kubernetes. Source, documentation and issues are on GitHub:
[Bevisera-AS/shyft-deployment](https://github.com/Bevisera-AS/shyft-deployment).

## Use it

```sh
helm repo add shyft https://bevisera-as.github.io/shyft-deployment
helm repo update shyft
helm install shyft-hydrology shyft/shyft-hydrology --namespace shyft --create-namespace
helm test shyft-hydrology --namespace shyft
```

`helm search repo shyft --versions` lists every published version.

## Verify a package

Every package has a build-provenance attestation from the GitHub Actions run that built it:

```sh
helm pull shyft/shyft-hydrology --version <version>
gh attestation verify shyft-hydrology-<version>.tgz --repo Bevisera-AS/shyft-deployment
```

The repository moved from `lazyoldbear/shyft-deployment` on 2026-11-19. 0.0.3, published before the move, was
attested there: verify it with `--owner lazyoldbear` in place of `--repo`.

## Licence

[MIT](https://github.com/Bevisera-AS/shyft-deployment/blob/master/LICENSE).
