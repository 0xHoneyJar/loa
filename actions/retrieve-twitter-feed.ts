"use server";

export async function retrieveTwitterFeed() {
  // Fetch the user's tweets
  const response = await fetch(
    `https://api.socialdata.tools/twitter/user/1610189982395670528/tweets`,
    {
      headers: {
        Authorization: `Bearer ${process.env.BEARER_TOKEN}`,
      },
    },
  );

  const res = await response.json();
  return res.tweets
}
