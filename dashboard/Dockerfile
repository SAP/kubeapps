# Copyright 2018-2024 the Kubeapps contributors.
# SPDX-License-Identifier: Apache-2.0

FROM node:24-alpine3.21 AS build

RUN apk add python3 make build-base gcc g++ libc-dev

WORKDIR /app

COPY package.json yarn.lock /app/
RUN CXXFLAGS="-std=c++20" yarn install --frozen-lockfile

RUN mkdir /app/src
COPY . /app
RUN yarn run prettier-check && yarn run ts-compile-check
RUN yarn run build

FROM ghcr.io/sap/kubeapps/bitnami-deprecated-nginx:1.29.1
COPY --from=build /app/build /app
