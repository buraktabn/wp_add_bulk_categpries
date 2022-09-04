## WordPress Category Injector

Add bulk nested categories into WordPress WooCommerce with JWT

#### Compile
```sh
dart compile exe bin/wp_category_injector.dart -o bin/app
```

#### Run
```sh
./bin/app run --wp-url localhost -u admin -p admin -d ./data.txt
```

#### Using docker
```sh
docker compose up
```