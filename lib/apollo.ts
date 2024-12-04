import { GRAPHQL_ENDPOINT, GRAPHQL_HC_ENDPOINT } from "@/constants/api";
import { ApolloClient, HttpLink, InMemoryCache } from "@apollo/client";

export function createApolloClient() {
  return new ApolloClient({
    link: new HttpLink({
      uri: GRAPHQL_ENDPOINT,
    }),
    cache: new InMemoryCache(),
  });
}

export function createApolloClientHC() {
  return new ApolloClient({
    link: new HttpLink({
      uri: GRAPHQL_HC_ENDPOINT,
    }),
    cache: new InMemoryCache(),
  });
}
