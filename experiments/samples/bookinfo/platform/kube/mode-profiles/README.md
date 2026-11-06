# Dependency mode profiles

The profile directories apply the source-resource annotation
`dependency.kubedepguard.io/mode` to the declared Bookinfo workload.

```sh
./enforce/deploy.sh
./warn/deploy.sh
```

Both scripts first deploy and verify the unannotated Bookinfo baseline, then
annotate its source resources. This ordering makes `enforce` safe to enable:
all referenced ConfigMaps, Secrets, PVCs, Services, and selected Pods already
exist when enforcement begins. The `warn` profile uses the same ordering so
its Event output stays attributable to the test case rather than installation.

Run the dependency matrix under a profile with:

```sh
../dependency-cases/run-cases.sh --mode enforce
../dependency-cases/run-cases.sh --mode warn
```
