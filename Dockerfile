FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY . .
RUN if [ -f src/HuTube.Api/HuTube.Api.csproj ]; then \
        dotnet publish src/HuTube.Api/HuTube.Api.csproj -c Release -o /app; \
    else \
        dotnet publish backend/src/HuTube.Api/HuTube.Api.csproj -c Release -o /app; \
    fi
FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /app .
ARG HUTUBE_COMMIT_SHA=local
ENV HUTUBE_COMMIT_SHA=$HUTUBE_COMMIT_SHA
ENV ASPNETCORE_URLS=http://+:8080
ENV ASPNETCORE_HTTP_PORTS=""
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && install -d -m 0755 /usr/share/postgresql-common/pgdg \
    && curl --fail --silent --show-error --location https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        --output /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
    && printf 'deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt %s-pgdg main\n' "$(. /etc/os-release && printf '%s' "$VERSION_CODENAME")" \
        > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends postgresql-client-18 \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /app/.work/mail /app/uploads \
    && chown -R $APP_UID:$APP_UID /app/.work /app/uploads
USER $APP_UID
EXPOSE 8080
ENTRYPOINT ["dotnet", "HuTube.Api.dll"]
