FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY . .
RUN dotnet publish src/HuTube.Api/HuTube.Api.csproj -c Release -o /app
FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /app .
ARG HUTUBE_COMMIT_SHA=local
ENV HUTUBE_COMMIT_SHA=$HUTUBE_COMMIT_SHA
ENV ASPNETCORE_URLS=http://+:8080
RUN mkdir -p /app/.work/mail && chown -R $APP_UID:$APP_UID /app/.work
USER $APP_UID
EXPOSE 8080
ENTRYPOINT ["dotnet", "HuTube.Api.dll"]
