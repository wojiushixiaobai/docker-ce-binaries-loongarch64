docker build -t dokcer-static .
docker run --rm -v "$(pwd)"/dist:/dist dokcer-static
ls -al "$(pwd)"/dist
