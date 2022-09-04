FROM dart:latest AS build

WORKDIR /app
COPY . .
RUN dart pub get
RUN dart compile exe bin/wp_category_injector.dart -o bin/app

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/bin/app /app/bin/
COPY --from=build /app/data.txt /data.txt

EXPOSE 8080
ENV PORT=8080
ENTRYPOINT ["/app/bin/app"]
