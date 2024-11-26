import { ApolloClient, HttpLink, InMemoryCache } from "@apollo/client";

export function createApolloClient() {
  return new ApolloClient({
    link: new HttpLink({
      uri: "https://the-honey-jar.squids.live/ecosystem-squid/v/v1/graphql",
    }),
    cache: new InMemoryCache(),
  });
}
