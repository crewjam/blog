FROM ruby
RUN apt-get update && apt-get install node -y
RUN gem install jekyll jekyll-sitemap
WORKDIR /opt/site
CMD jekyll serve
