# Pair-HMM accelerator using CAPI SNAP & Apache Arrow

## Configuration
### Submodules
`git submodule update --init`

### Fletcher
```
mkdir fletcher/build
cd fletcher/build
cd build && cmake .. -DPLATFORM_SNAP=ON
make
sudo make install
```

### Add IP cores to SNAP framework
```
chmod +x add_ip.sh
./add_ip.sh
```
