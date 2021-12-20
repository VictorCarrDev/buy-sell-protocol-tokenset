FROM node:14

WORKDIR /app

COPY package.json .

RUN yarn

COPY . .

ARG Al_KEY

ENV ALCHEMY_KEY=${Al_KEY}

CMD [ "npx", "hardhat","node" ]

EXPOSE 8545