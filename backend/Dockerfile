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
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends libgssapi-krb5-2 \
    && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /app/.work/mail && chown -R $APP_UID:$APP_UID /app/.work
USER $APP_UID
EXPOSE 8080
ENTRYPOINT ["dotnet", "HuTube.Api.dll"]
